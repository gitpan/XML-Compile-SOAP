# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use warnings;
use strict;

package XML::Compile::SOAP::Client;
use vars '$VERSION';
$VERSION = '0.71';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Util qw/unpack_type/;
use XML::Compile::SOAP::Trace;
use Time::HiRes        qw/time/;


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }


sub _rpcin_default($@)
{   my ($soap, @msgs) = @_;
    my $tree   = $soap->dec(@msgs) or return ();
    $soap->decSimplify($tree);
}

my $rr = 'request-response';
sub compileClient(@)
{   my ($self, %args) = @_;

    my $name   = $args{name};
    my $rpcout = $args{rpcout};

    unless(defined $name)
    {   (undef, $name) = unpack_type $rpcout
            if $rpcout && ! ref $rpcout;
        $name ||= 'unnamed';
    }

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
        my ($data, $charset) = UNIVERSAL::isa($_[0], 'HASH') ? @_ : ({@_});
        my $req   = $encode->($data, $charset);

        my %trace;
        my $ans   = $transport->($req, \%trace);

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

    # Outgoing messages

    defined $rpcout
        or return $core;

    my $rpc_encoder
      = UNIVERSAL::isa($rpcout, 'CODE') ? $rpcout
      : $self->schemas->compile
        ( WRITER => $rpcout
        , include_namespaces => 1
        , elements_qualified => 'TOP'
        );

    my $out = sub
      {    @_ && @_ % 2  # auto-collect rpc parameters
      ? ( rpc => [$rpc_encoder, shift], @_ ) # possible header blocks
      : ( rpc => [$rpc_encoder, [@_] ]     ) # rpc body only
      };

    # Incoming messages

    my $rpcin = $args{rpcin} ||
      (UNIVERSAL::isa($rpcout, 'CODE') ? \&_rpcin_default : $rpcout.'Response');

    # RPC intelligence wrapper

    if(UNIVERSAL::isa($rpcin, 'CODE'))     # rpc-encoded
    {   return sub
        {   my ($dec, $trace) = $core->($out->(@_));
            return wantarray ? ($dec, $trace) : $dec
                if $dec->{Fault};

            my @raw;
            foreach my $k (keys %$dec)
            {   my $node = $dec->{$k};
                if(   ref $node eq 'ARRAY' && @$node
                   && $node->[0]->isa('XML::LibXML::Element'))
                {   push @raw, @$node;
                    delete $dec->{$k};
                }
                elsif(ref $node && $node->isa('XML::LibXML::Element'))
                {   push @raw, delete $dec->{$k};
                }
            }

            if(@raw)
            {   $self->startDecoding(simplify => 1);
                my @parsed = $rpcin->($self, @raw);
                if(@parsed==1) { $dec = $parsed[0] }
                else
                {   while(@parsed)
                    {   my $n = shift @parsed;
                        $dec->{$n} = shift @parsed;
                    }
                }
            }

            wantarray ? ($dec, $trace) : $dec;
        };
    }
    else                                   # rpc-literal
    {   my $rpc_decoder = $self->schemas->compile(READER => $rpcin);
        (undef, my $rpcin_local) = unpack_type $rpcin;

        return sub
        {   my ($dec, $trace) = $core->($out->(@_));
            $dec->{$rpcin_local} = $rpc_decoder->(delete $dec->{$rpcin})
              if $dec->{$rpcin};
            wantarray ? ($dec, $trace) : $dec;
        };
    }
}

#------------------------------------------------


my $fake_server;
sub fakeServer()
{   return $fake_server if @_==1;

    my $server = $_[1];
    defined $server
        or return $fake_server = undef;

    ref $server && $server->isa('XML::Compile::SOAP::Tester')
        or error __x"fake server isn't a XML::Compile::SOAP::Tester";

    $fake_server = $server;
}

#------------------------------------------------


1;
