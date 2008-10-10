# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '0.78';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::SOAP::Util qw/:soap11/;


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }

sub init($)
{  my ($self, $args) = @_;
   $self->{role} = $self->roleAbbreviation($args->{role} || 'NEXT');
   $self;
}


sub role() {shift->{role}}


sub compileHandler(@)
{   my ($self, %args) = @_;

    my $decode = $args{decode};
    my $encode = $args{encode}     || $self->compileMessage('SENDER');
    my $name   = $args{name}
        or error __x"each server handler requires a name";
    my $selector = $args{selector} || sub {0};

    # even without callback, we will validate
    my $callback = $args{callback};

    my $invalid = __x"{version} operation {name} called with invalid data"
      , version => $self->version, name => $name;

    my $empty   = __x"{version} operation {name} did not produce an answer"
      , version => $self->version, name => $name;

    sub
    {   my ($name, $xmlin, $info) = @_;
        $selector->($xmlin, $info) or return;
        trace __x"procedure {name} selected", name => $name;

        my ($data, $answer);

        if($decode)
        {   $data = try { $decode->($xmlin) };
            if($@)
            {   my $exception = $@->wasFatal;
                $exception->throw(reason => 'info');
                info __x"callback {name} validation failed", name => $name;
                $answer = $self->faultValidationFailed($invalid, $exception);
            }
        }
        else
        {   $data = $xmlin;
        }

        $answer = $callback->($self, $data)
            if $data && !$answer;

        return $answer
            if UNIVERSAL::isa($answer, 'XML::LibXML::Document');

        unless($answer)
        {   info __x"callback {name} did not return an answer", name => $name;
            $answer = $self->faultNoAnswerProduced($empty);
        }

        $encode->($answer);
    };
}


sub compileFilter(@)
{   my ($self, %args) = @_;
    my $nodetype = ($args{body} || [])->[1];

    # called with (XML, INFO)
      defined $nodetype
    ? sub { my $f =  $_[1]->{body}[0]; defined $f && $f eq $nodetype }
    : sub { !defined $_[1]->{body}[0] };  # empty body
}


sub faultWriter()
{   my $thing = shift;
    my $self  = ref $thing ? $thing : $thing->new;
    $self->compileMessage('SENDER');
}

1;
