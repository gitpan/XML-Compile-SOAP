# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::Transport;
use vars '$VERSION';
$VERSION = '0.63';
use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::LibXML ();
use Time::HiRes qw/time/;


sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{charset} = $args->{charset} || 'utf-8';

    my $addr  = $args->{address} || 'localhost';
    my @addrs = ref $addr eq 'ARRAY' ? @$addr : $addr;

    $self->{addrs} = \@addrs;

    $self;
}

#-------------------------------------


sub charset() {shift->{charset}}


sub addresses() { @{shift->{addrs}} }


sub address()
{   my $addrs = shift->{addrs};
    @$addrs==1 ? $addrs->[0] : $addrs->[rand @$addrs];
}

#-------------------------------------


my $parser = XML::LibXML->new;
sub compileClient(@)
{   my ($self, %args) = @_;
    my $call  = $self->_prepare_call(\%args);

    sub
    {   my ($xmlout, $trace) = @_;
        my $start     = time;
        my $textout   = ref $xmlout ? $xmlout->toString : $xmlout;

        my $stringify = time;
        $trace->{transport_start}  = $start;

        my $textin    = $call->($textout, $trace);
        my $connected = time;

        my $xmlin;
        if($textin)
        {   $xmlin = eval {$parser->parse_string($textin)};
            $trace->{error} = $@ if $@;
        }
        else
        {   $trace->{error} = 'no xml as answer';
        }

        my $end = $trace->{transport_end} = time;

        $trace->{stringify_elapse} = $stringify - $start;
        $trace->{connect_elapse}   = $connected - $stringify;
        $trace->{parse_elapse}     = $end - $connected;
        $trace->{transport_elapse} = $end - $start;
        $xmlin;
    }
}

sub _prepare_call($) { panic "not implemented" }


1;
