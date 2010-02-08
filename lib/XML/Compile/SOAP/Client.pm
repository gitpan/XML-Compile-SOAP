# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Client;
use vars '$VERSION';
$VERSION = '2.10';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Util qw/unpack_type/;
use XML::Compile::SOAP::Trace;
use Time::HiRes        qw/time/;


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }


my $rr = 'request-response';
sub compileClient(@)
{   my ($self, %args) = @_;

    my $name   = $args{name};
    my $kind = $args{kind} || $rr;
    $kind eq $rr || $kind eq 'one-way'
        or error __x"operation direction `{kind}' not supported for {name}"
             , rr => $rr, kind => $kind, name => $name;

    my $encode = $args{encode}
        or error __x"encode for client {name} required", name => $name;

    my $decode = $args{decode}
        or error __x"decode for client {name} required", name => $name;

    my $transport = $args{transport}
        or error __x"transport for client {name} required", name => $name;

    if(ref $transport eq 'CODE') { ; }
    elsif(UNIVERSAL::isa($transport, 'XML::Compile::Transport::SOAPHTTP'))
    {   $transport = $transport->compileClient;
    }
    else
    {   error __x"transport for client {name} is code ref or {type} object, not {is}"
          , name => $name, type => 'XML::Compile::Transport::SOAPHTTP'
          , is => (ref $transport || $transport);
    }

    my $core = sub
    {   my $start = time;
        my ($data, $charset)
          = UNIVERSAL::isa($_[0], 'HASH') ? @_
          : @_%2==0 ? ({@_}, undef)
          : error __x"client `{name}' called with odd length parameter list"
              , name => $name;
        my ($req, $mtom) = $encode->($data, $charset);

        my %trace;
        my $ans   = $transport->($req, \%trace, $mtom);

        wantarray or return
            UNIVERSAL::isa($ans, 'XML::LibXML::Node') ? $decode->($ans) : $ans;

        $trace{start}  = $start;
        $trace{encode_elapse} = $trace{transport_start} - $start;

        if(UNIVERSAL::isa($ans, 'XML::LibXML::Node'))
        {   $ans = $decode->($ans);
            my $end = time;
            $trace{decode_elapse} = $end - $trace{transport_end};
            $trace{elapse} = $end - $start;
        }
        else
        {   $trace{elapse} = $trace{transport_end} - $start;
        }

        ($ans, XML::Compile::SOAP::Trace->new(\%trace));
    };
}

#------------------------------------------------


1;
