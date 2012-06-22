# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::Transport;
use vars '$VERSION';
$VERSION = '2.27';

use base 'XML::Compile::SOAP::Extension';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::LibXML ();
use Time::HiRes qw/time/;


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
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
    my $call   = $self->_prepare_call(\%args);
    my $kind   = $args{kind} || 'request-response';
    my $format = $args{xml_format} || 0;

    sub
    {   my ($xmlout, $trace, $mtom) = @_;
        my $start     = time;
        my $textout   = ref $xmlout ? $xmlout->toString($format) : $xmlout;
#warn $xmlout->toString(1);   # show message sent

        my $stringify = time;
        $trace->{stringify_elapse} = $stringify - $start;
        $trace->{transport_start}  = $start;

        my ($textin, $xops) = eval { $call->(\$textout, $trace, $mtom) };
        my $connected = time;
        $trace->{connect_elapse}   = $connected - $stringify;
        if($@)
        {   $trace->{error} = $@;
            return;
        }

        my $xmlin;
        if($textin)
        {   $xmlin = eval {$parser->parse_string($$textin)};
            if($@) { $trace->{error} = $@ }
            else   { $trace->{response_dom} = $xmlin }
        }

        my $answer = $xmlin;
        if($kind eq 'one-way')
        {   my $response = $trace->{http_response};
            my $code = defined $response ? $response->code : -1;
            if($code==202) { $answer ||= {} }
            else { $trace->{error} = "call failed with code $code" }
        }
        elsif(!$xmlin)
        {   $trace->{error} ||= 'no xml as answer';
        }

        my $end = $trace->{transport_end} = time;

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
