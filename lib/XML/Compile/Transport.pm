# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::Transport;
use vars '$VERSION';
$VERSION = '2.11';

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

    my $addr  = $args->{address} || 'http://localhost';
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
    my $kind  = $args{kind} || 'request-response';

    sub
    {   my ($xmlout, $trace, $mtom) = @_;
        my $start     = time;
        my $textout   = ref $xmlout ? $xmlout->toString : $xmlout;

        my $stringify = time;
        $trace->{transport_start}  = $start;

        my ($textin, $xops) = $call->(\$textout, $trace, $mtom);
        my $connected = time;

        my $xmlin;
        if($textin)
        {   $xmlin = eval {$parser->parse_string($$textin)};
            $trace->{error} = $@ if $@;
        }

        my $answer;
        if($kind eq 'one-way')
        {   my $response = $trace->{http_response};
            my $code = defined $response ? $response->code : -1;
            if($code==202) { $answer = $xmlin || {} }
            else { $trace->{error} = "call failed with code $code" }
        }
        elsif($xmlin) { $answer = $xmlin }
        else { $trace->{error} ||= 'no xml as answer' }

        my $end = $trace->{transport_end} = time;

        $trace->{stringify_elapse} = $stringify - $start;
        $trace->{connect_elapse}   = $connected - $stringify;
        $trace->{parse_elapse}     = $end - $connected;
        $trace->{transport_elapse} = $end - $start;

        wantarray || ! keys %$xops
            or warning "loosing received XOPs";

        wantarray ? ($answer, $xops) : $answer;
    }
}

sub _prepare_call($) { panic "not implemented" }

#--------------------------------------


{   my %registered;
    sub register($)   { my ($class, $uri) = @_; $registered{$uri} = $class }
    sub plugin($)     { my ($class, $uri) = @_; $registered{$uri} }
    sub registered($) { values %registered }
}

#--------------------------------------


1;
