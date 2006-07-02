package MojoMojo::Controller::User;

use strict;
use base 'Catalyst::Controller';

use Digest::MD5 qw/md5_hex/;
use Data::FormValidator::Constraints::DateTime qw(:all);

my $auth_class = MojoMojo->config->{auth_class};

=head1 NAME

MojoMojo::Controller::User - Login/User Management Controller


=head1 DESCRIPTION

This controller allows user to Log In and Log out.


=head1 ACTIONS

=over 4

=item login (/.login)

Log in through the authentication system.

=cut

sub login : Global {
    my ($self,$c) = @_;
    $c->stash->{message} = 'please enter username & password';
    if ( $c->req->params->{login} ) {
        if ( $c->login() ) {
	    $c->stash->{user}=$c->user->obj;
            $c->res->redirect($c->stash->{user}->link)
                unless $c->stash->{template};
            return;
        }
        else {
            $c->stash->{message} = 'could not authenticate that login.';
        }
    }
    $c->stash->{template} ||= "user/login.tt";
}

=item logout (/.logout)

Log out the user

=cut

sub logout : Global {
    my ($self,$c) = @_;
    $c->logout;
    undef $c->stash->{user};
    $c->forward('/page/view');
}

=item users (/.users)

Show a list of the active users with a link to their page.

=cut

sub users : Global {
   my ($elf,$c,$tag)  = @_;   
   my $res = $c->model("DBIC::Person")->search(
      { active=>1 } , { 
      page     => $c->req->param('page')||1,
      rows     => 20,
      order_by => 'login' } );
   $c->stash->{users}=$res;
   $c->stash->{pager}=$res->pager;
   $c->stash->{template}='user/list.tt';  
}

=item prefs

Main user preferences screen.

=cut

sub prefs : Global {
    my ( $self, $c ) = @_;
    $c->stash->{template}='user/prefs.tt';
    my @proto=@{$c->stash->{proto_pages}};
    $c->stash->{page_user}=$c->model("DBIC::Person")->get_user(
        $proto[0]->{name} || $c->stash->{page}->name_orig 
    );
    unless ($c->stash->{page_user} && (
        $c->stash->{page_user}->id eq $c->stash->{user}->id ||
        $c->stash->{user}->is_admin())) {
      $c->stash->{message}='Cannot find that user.';
      $c->stash->{template}='message.tt';
    };
}

=item password (/prefs/passwordy

Change password action.

B<template:> user/password.tt

=cut

sub password : Path('/prefs/password') {
    my ( $self, $c ) = @_;
    $c->forward('prefs');
    return if $c->stash->{message};
    $c->stash->{template}='user/password.tt';
    $c->form(
      required=>[qw/current pass again/]
      );
    unless ( $c->form->has_missing || $c->form->has_invalid ) {
      if ($c->form->valid('again') ne $c->form->valid('pass')) {
        $c->stash->{message}='Passwords did not match.';
        return;
      }
      unless ($c->stash->{user}->valid_pass($c->form->valid('current'))) {
        $c->stash->{message}='Invalid password.';
        return;
      }
      $c->stash->{user}->pass($c->form->valid('pass'));
      $c->stash->{user}->update();
      $c->stash->{message}='Your password has been updated';
    }
    $c->stash->{message} ||= 'please fill out all fields';
}

=item register (/.register)

Show new user registration form.

B<template:> user/register.tt

=cut

sub register : Global {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'user/register.tt';
    $c->stash->{message}='Please fill in the following information to '.
    'register. All fields are mandatory.';
}

=item do_register (/.register)

New user registration processing.

B<template:> user/password.tt /  user/validate.tt

=cut

sub do_register : Global {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'user/register.tt';
    $c->form(required => [qw(login name pass confirm email)],
             defaults  => { active => -1 }, 
             constraints => $c->model("DBIC::Person")->registration_profile(
	     $c->model('DBIC')->schema));
    if ($c->form->has_missing) {
        $c->stash->{message}='You have to fill in all fields.'. 
        'the following are missing: <b>'.
        join(', ',$c->form->missing()).'</b>';
    } elsif ($c->form->has_invalid) {
        $c->stash->{message}='Some fields are invalid. Please '.
                             'correct them and try again:';
    } else {
	delete $c->form->{valid}->{confirm};
        my $user=$c->model("DBIC::Person")->create($c->form->{valid});
        $c->forward('/user/login');
        $c->pref('entropy') || $c->pref('entropy',rand);
        $c->email( header => [
                From    => $c->form->valid('email'),
                To      => $c->form->valid('email'),
                Subject => '[MojoMojo] New User Validation'
            ],
            body => 'Hi. This is a mail to validate your email address, '.
            $c->form->valid('name').'. To confirm, please click '.
            "the url below:\n\n".$c->req->base.'/.validate/'.
            $user->id.'/'.md5_hex$c->form->valid('email').$c->pref('entropy')
        );
        $c->stash->{user}=$user;
        $c->stash->{template}='user/validate.tt';
    }
}    

=item validate (/.validate)

Validation of user email. Will accept a md5_hex mailed to the user
earlier. Non-validated users will only be able to log out.

=cut

sub validate : Global {
    my ($self,$c,$user,$check)=@_;
    $user=$c->model("DBIC::Person")->find($user);
    if($check = md5_hex($user->email.$c->pref('entropy'))) {
        $user->active(0);
        $user->update();
        if ($c->stash->{user}) {
            $c->res->redirect($c->req->base.$c->stash->{user}->link);
        } else {
            $c->stash->{message}='Welcome, '.$user->name.' your email is validated. Please log in.';
            $c->stash->{template}='user/login.tt';
        }
        return;
    }
    $c->stash->{template}='user/validate.tt';
}

=item profile .profile

Show user profile.

=cut

sub profile : Global {
    my ($self,$c)=@_;
    my $page=$c->stash->{page};
    my $user=$c->model("DBIC::Person")->get_user($page->name_orig);
    if ( $user ) {
          $c->stash->{person}=$user;
          $c->stash->{template}='user/profile.tt';
    } else { 
        $c->stash->{template}='message.tt';
        $c->stash->{message}='User not found!';
    }
}

sub editprofile : Global {
    my ($self,$c)=@_;
    my $page=$c->stash->{page};
    my $user=$c->model("DBIC::Person")->get_user($page->name_orig);
    if ( $user && $c->stash->{user} && ($c->stash->{user}->is_admin || 
		   $user->id eq $c->stash->{user}->id ) ) {
          $c->stash->{person}=$user;
	  $c->stash->{years} = [ 1905 .. 2005 ];
	  $c->stash->{months} = [ 1 .. 12 ];
	  $c->stash->{days} = [ 1 .. 31 ];
          $c->stash->{template}='user/editprofile.tt';
    } else { 
        $c->stash->{template}='message.tt';
        $c->stash->{message}='User not found!';
    }

}

sub do_editprofile : Global {
    my ( $self, $c ) = @_;
    $c->form(required => [qw(name email)],
	     optional => [$c->model("DBIC::Person")->result_source->columns],
             defaults  => { gender => undef }, 
	     constraint_methods => {
		born => ymd_to_datetime(qw(birth_year birth_month birth_day))
	     },
	     untaint_all_constraints=>1,
           );

    if ($c->form->has_missing) {
        $c->stash->{message}='You have to fill in all required fields.'. 
        'the following are missing: <b>'.
        join(', ',$c->form->missing()).'</b>';
    } elsif ($c->form->has_invalid) {
        $c->stash->{message}='Some fields are invalid. Please '.
                             'correct them and try again:';
    } else {
	my $user=$c->model("DBIC::Person")->get_user(
	    $c->stash->{page}->name_orig);
	$user->set_columns($c->form->{valid});
	$user->update();
	return $c->forward('profile');
    }
    $c->forward('editprofile');
}

=back

=head1 AUTHOR

David Naughton <naughton@cpan.org>, 
Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This library is free software . You can redistribute it and/or modify
it under the same terms as perl itself.

=cut

1;