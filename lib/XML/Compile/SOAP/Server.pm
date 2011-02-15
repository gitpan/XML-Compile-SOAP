# Copyrights 2007-2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '2.23';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::SOAP::Util qw/:soap11/;
use HTTP::Status qw/RC_OK RC_BAD_REQUEST RC_NOT_ACCEPTABLE
   RC_INTERNAL_SERVER_ERROR/;


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }

sub init($)
{  my ($self, $args) = @_;
   $self->{role} = $self->roleURI($args->{role} || 'NEXT') || $args->{role};
   $self;
}

#---------------------------------


sub role() {shift->{role}}

#---------------------------------


sub compileHandler(@)
{   my ($self, %args) = @_;

    my $decode = $args{decode};
    my $encode = $args{encode}     || $self->compileMessage('SENDER');
    my $name   = $args{name}
        or error __x"each server handler requires a name";
    my $selector = $args{selector} || sub {0};

    # even without callback, we will validate
    my $callback = $args{callback};

    sub
    {   my ($name, $xmlin, $info) = @_;
        $selector->($xmlin, $info) or return;
        trace __x"procedure {name} selected", name => $name;

        my $data;
        if($decode)
        {   $data = try { $decode->($xmlin) };
            if($@)
            {   $@->wasFatal->throw(reason => 'INFO', is_fatal => 0);
                return ( RC_NOT_ACCEPTABLE, 'input validation failed'
                   , $self->faultValidationFailed($name, $@->wasFatal))
            }
        }
        else
        {   $data = $xmlin;
        }

        my $answer = $callback->($self, $data);
        unless(defined $answer)
        {   alert "procedure {name} did not produce an answer", name=> $name;
            return ( RC_INTERNAL_SERVER_ERROR, 'no answer produced'
                      , $self->faultNoAnswerProduced($name));
        }

        if(ref $answer ne 'HASH')
        {   alert "procedure {name} did not return a HASH", name => $name;
            return ( RC_INTERNAL_SERVER_ERROR, 'invalid answer produced'
                      , $self->faultNoAnswerProduced($name));
        }

        my $rc = (delete $answer->{_RETURN_CODE})
              || ($answer->{Fault} ? RC_BAD_REQUEST : RC_OK);
        my $rc_txt = delete $answer->{_RETURN_TEXT} || 'Answer included';

        my $xmlout = try { $encode->($answer) };
        $@ or return ($rc, $rc_txt, $xmlout);

        my $fatal = $@->wasFatal;
        $fatal->throw(reason => 'ALERT', is_fatal => 0);

        ( RC_INTERNAL_SERVER_ERROR, 'created response not valid'
        , $self->faultResponseInvalid($name, $fatal)
        );
    };
}


sub compileFilter(@)
{   my ($self, %args) = @_;
    my $nodetype;
    if(my $first    = $args{body}{parts}[0])
    {   $nodetype = $first->{element}
#           or panic "cannot handle type parameter in server filter";
            || $args{body}{procedure};  # rpc-literal "type"
    }

    # called with (XML, INFO)
      defined $nodetype
    ? sub { my $f =  $_[1]->{body}[0]; defined $f && $f eq $nodetype }
    : sub { !defined $_[1]->{body}[0] };  # empty body
}


sub faultWriter()
{   my $thing = shift;
    my $self  = ref $thing ? $thing : $thing->new;
    $self->{fault_writer} ||= $self->compileMessage('SENDER');
}

1;
