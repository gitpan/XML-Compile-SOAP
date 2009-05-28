# Copyrights 2007-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '2.05';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::SOAP::Util qw/:soap11/;
use HTTP::Status qw/RC_OK RC_NOT_ACCEPTABLE RC_INTERNAL_SERVER_ERROR/;


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }

sub init($)
{  my ($self, $args) = @_;
   $self->{role} = $self->roleAbbreviation($args->{role} || 'NEXT');
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

        my ($data, $answer);

        if($decode)
        {   $data = try { $decode->($xmlin) };
            return ( RC_NOT_ACCEPTABLE, 'input validation failed'
                   , $self->faultValidationFailed($name, $@->wasFatal))
                if $@;
        }
        else
        {   $data = $xmlin;
        }

        $answer = $callback->($self, $data);

        defined $answer
            or return ( RC_INTERNAL_SERVER_ERROR, 'no answer produced'
                      , $self->faultNoAnswerProduced($name));

        !ref $answer || ref $answer eq 'HASH'
            or return $answer;   # something ready or half ready

        my $xmlout = try { $encode->($answer) };
        $@ or return (RC_OK, 'Answer included', $xmlout);

        ( RC_INTERNAL_SERVER_ERROR, 'created response not valid'
        , $self->faultResponseInvalid($name, $@->wasFatal)
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
