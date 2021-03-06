package Weixin::Message;
use Weixin::Util;
use List::Util qw(first);
use Weixin::Message::Constant;
use Weixin::Client::Private::_send_text_msg;

sub _parse_send_status_data {
    my $self = shift;
    my $json = shift;
    if(defined $json){
        my $d = $self->json_decode($json);
        return {is_success => 0,status=>"数据格式错误"} unless defined $d;
        return {is_success => 0,status=>encode_utf8($d->{BaseRequest}{ErrMsg})} if $d->{BaseRequest}{Ret}!=0; 
        return {is_success => 1,status=>"发送成功"};
    }
    else{
        return {is_success => 0,status=>"请求失败"};
    } 
}

my %logout_code = qw(
    1100    0
    1101    1
    1102    1
    1205    1
);
sub _parse_sync_data {
    my $self = shift;
    my $d = shift;
    if(first {$d->{BaseResponse}{Ret} == $_} keys %logout_code  ){
        $self->logout($logout_code{$d->{BaseResponse}{Ret}});
        $self->stop();
    }
    elsif($d->{BaseResponse}{Ret} !=0){
        console "收到无法识别消息，已将其忽略\n";
        return; 
    }
    $self->sync_key = $d->{SyncKey} if $d->{SyncKey}{Count}!=0;
    if($d->{AddMsgCount} != 0){
        my @key = qw(
            CreateTime
            FromId
            ToId
            Content
            MsgType
            MsgId
        );
        for (@{$d->{AddMsgList}}){
            my $msg = {};
            $_->{FromId} = $_->{FromUserName};delete $_->{FromUserName};
            $_->{ToId} = $_->{ToUserName};delete $_->{ToUserName};
            @{$msg}{@key} = map {$_=encode_utf8($_);$_} @{$_}{@key};
            $self->_add_msg($msg);
        }
    }
    if($d->{DelContactCount}!=0){    
    }
    if($d->{ModContactCount}!=0){
        
    }
    if($d->{ModChatRoomMemberCount}!=0){
    
    }
    if($d->{ContinueFlag}!=0){
        $self->_sync();
    }
    else{
        $self->_synccheck();
    }
     
}

sub _add_msg{
    my $self = shift;
    my $msg  = shift;
    $msg->{TTL} = 5;
    if($msg->{MsgType} eq MM_DATA_TEXT){
        $msg->{MsgType} = "text";
        if($msg->{FromId} eq $self->{_data}{user}{Id}){
            $msg->{MsgClass} = "send";
        }
        elsif($msg->{ToId} eq $self->{_data}{user}{Id}){
            $msg->{MsgClass} = "recv";
        }
        
        if($msg->{MsgClass} eq "send"){
            $msg->{Type}    = index($msg->{ToId},'@@')==0?"chatroom_message":"friend_message";
            if($msg->{Type} eq "friend_message"){
                my $friend = $self->search_friend(Id=>$msg->{ToId}) || {}; 
                $msg->{FromNickName} = "我";
                $msg->{FromRemarkName} = "我";
                $msg->{FromUin} = $self->{_data}{user}{Uin};
                $msg->{ToUin} = $friend->{Uin};
                $msg->{ToNickName} = $friend->{NickName};
                $msg->{ToRemarkName} = $friend->{RemarkName};
            }
            elsif($msg->{Type} eq "chatroom_message"){
                my $chatroom = $self->search_chatroom(ChatRoomId=>$msg->{ToId}) || {};
                $msg->{FromNickName} = "我";
                $msg->{FromRemarkName} = undef;
                $msg->{FromUin} = $self->{_data}{user}{Uin};
                $msg->{ToUin} = $chatroom->{ChatRoomUin}; 
                $msg->{ToNickName} = $chatroom->{ChatRoomName};
                $msg->{ToRemarkName} = undef;
            }
            $msg = $self->_mk_ro_accessors($msg,"Send");
        }
        elsif($msg->{MsgClass} eq "recv"){
            $msg->{Type}    = index($msg->{FromId},'@@')==0?"chatroom_message":"friend_message"; 
            if($msg->{Type} eq "friend_message"){
                my $friend = $self->search_friend(Id=>$msg->{FromId}) || {}; 
                $msg->{FromNickName} = $friend->{NickName};
                $msg->{FromRemarkName} = $friend->{RemarkName};
                $msg->{FromUin} = $friend->{Uin};;
                $msg->{ToUin} = $self->{_data}{user}{Uin};
                $msg->{ToNickName} = "我";
                $msg->{ToRemarkName} = undef;
            }
            elsif($msg->{Type} eq "chatroom_message"){
                my ($chatroom_member_id,$content) = $msg->{Content}=~/^(\@.+):<br\/>(.*)/g; 
                $msg->{Content} = $content;
                my $member = $self->search_chatroom_member(ChatRoomId=>$msg->{FromId},Id=>$chatroom_member_id) || {};
                $msg->{FromNickName} = $member->{NickName};
                $msg->{FromId}       = $member->{Id};
                $msg->{FromRemarkName} = undef;
                $msg->{FromUin} = $member->{Uin};;
                $msg->{ToUin} = $self->{_data}{user}{Uin};
                $msg->{ToNickName} = "我";
                $msg->{ToRemarkName} = undef;
                $msg->{ChatRoomName} = $member->{ChatRoomName};
                $msg->{ChatRoomUin} = $member->{ChatRoomUin};
                $msg->{ChatRoomId}  = $member->{ChatRoomId};
            }
            $msg = $self->_mk_ro_accessors($msg,"Recv");
        }
        
        $self->{_receive_message_queue}->put($msg);
    }
    elsif($msg->{MsgType} eq MM_DATA_STATUSNOTIFY){
    
    }
    elsif($msg->{MsgType} eq MM_DATA_SYSNOTICE){
        
    }
    elsif($msg->{MsgType} eq MM_DATA_APPMSG){
        
    }
    elsif($msg->{MsgType} eq MM_DATA_EMOJI){

    }
}
sub _del_friend{
    my $self = shift;
}
sub _mod_chatroom_member{
    my $self = shift;
}
sub _mod_friend{
    my $self = shift;
}
sub _mod_profile {
    my $self = shift;
}

sub _mk_ro_accessors {
    my $self = shift;
    my $msg =shift;
    my $msg_pkg = shift;
    no strict 'refs';
    for my $field (keys %$msg){
        *{__PACKAGE__ . "::${msg_pkg}::$field"} = sub{
            my $obj = shift;
            my $pkg = ref $obj;
            die "the value of \"$field\" in $pkg is read-only\n" if @_!=0;
            return $obj->{$field};
        };
    }
    return bless $msg,__PACKAGE__."::$msg_pkg";
}

sub send_friend_msg {
    my $self = shift;
    my ($friend,$content) = @_;
    unless(defined $friend and $friend->{Id}){
        console "send_friend_msg 参数无效\n";
        return;
    }
    unless($content){
        console "send_friend_msg 发送内容不能为空\n";
        return ;
    }
    my $msg = $self->_create_text_msg($friend,$content,"friend_message"); 
    $self->{_send_message_queue}->put($msg);
}

sub send_chatroom_msg {
    my $self = shift;
    my ($chatroom,$content) = @_;
    unless(defined $chatroom and $chatroom->{Id}){
        console "send_chatroom_msg 参数无效\n";
        return;
    }
    unless($content){
        console "send_chatroom_msg 发送内容不能为空\n";
        return ;
    }
    my $msg = $self->_create_text_msg($chatroom,$content,"chatroom_message");
    $self->{_send_message_queue}->put($msg);
}

sub reply_msg {
    my $self = shift;
    my $msg = shift;
    my $content = shift;
    return if $msg->{MsgClass} ne "recv";
    if($msg->{Type} eq "chatroom_message"){
        my $chatroom = $self->search_chatroom(Id=>$msg->{ChatRoomId});
        $self->send_chatroom_msg($chatroom,$content);
    }
    elsif($msg->{Type} eq "friend_message"){
        my $friend = $self->search_friend(Id=>$msg->{FromId});
        $self->send_friend_msg($friend,$content);
    }
}

sub _create_text_msg{
    my $self = shift;
    my ($obj,$content,$type)= @_;
    my $to_id;
    my $to_uin;
    my $to_nickname;
    my $remark_name;
    if($type eq "chatroom_message"){
        $to_id = $obj->{ChatRoomId};
        $to_uin = $obj->{ChatRoomUin};
        $to_nickname = $obj->{ChatRoomName}; 
    }
    elsif($type eq "friend_message"){
        $to_id = $obj->{Id};
        $to_uin = $obj->{Uin};
        $to_nickname = $obj->{NickName};
        $remark_name = $obj->{RemarkName};
    }
    my $t = $self->now();
    my $msg = {
        CreateTime  => time(),
        MsgId       => $t,
        Content     => $content,
        FromId      => $self->user->{Id},
        FromNickName=> "我",
        FromRemarkName => undef,
        FromUin     => $self->user->{Uin},
        ToId        => $to_id,
        ToNickName  => $to_nickname,
        ToRemarkName=> $remark_name, 
        ToUin       => $to_uin,
        MsgType     => "text",
        MsgClass    => "send", 
        Type        => $type,
        TTL         => 5,
    };      
    return $self->_mk_ro_accessors($msg,"Send"); 
}

1;
