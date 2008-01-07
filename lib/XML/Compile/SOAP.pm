# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::SOAP;
use vars '$VERSION';
$VERSION = '0.65';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile         ();
use XML::Compile::Util   qw/pack_type unpack_type/;
use XML::Compile::Schema ();

use Time::HiRes          qw/time/;


sub new($@)
{   my $class = shift;

    error __x"you can only instantiate sub-classes of {class}"
        if $class eq __PACKAGE__;

    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{envns}   = $args->{envelope_ns} || panic "no envelope namespace";
    $self->{encns}   = $args->{encoding_ns} || panic "no encoding namespace";
    $self->{schemans}= $args->{schema_ns}   || panic "no schema namespace";
    $self->{mimens}  = $args->{media_type}  || 'application/soap+xml';
    $self->{schemas} = $args->{schemas}     || XML::Compile::Schema->new;
    $self->{version} = $args->{version}     || panic "no version string";

    $self->{schemains} = $args->{schema_instance_ns}
      || $self->{schemans}.'-instance';

    $self;
}


sub version()    {shift->{version}}
sub envelopeNS() {shift->{envns}}
sub encodingNS() {shift->{encns}}
sub schemaNS()   {shift->{schemans}}
sub schemaInstanceNS() {shift->{schemains}}


sub schemas()    {shift->{schemas}}


sub prefixPreferences($$;$)
{   my ($self, $table, $new, $used) = @_;
    my @allns  = ref $new eq 'ARRAY' ? @$new : %$new;
    while(@allns)
    {   my ($prefix, $uri) = splice @allns, 0, 2;
        $table->{$uri} = {uri => $uri, prefix => $prefix, used => $used};
    }
    $table;
}


sub compileMessage($@)
{   my ($self, $direction, %args) = @_;
    $args{style} ||= 'document';

      $direction eq 'SENDER'   ? $self->sender(\%args)
    : $direction eq 'RECEIVER' ? $self->receiver(\%args)
    : error __x"message direction is 'SENDER' or 'RECEIVER', not `{dir}'"
         , dir => $direction;
}


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

    my $core = sub
    {   my $start = time;
        my ($data, $charset) = UNIVERSAL::isa($_[0], 'HASH') ? @_ : ({@_});
        my $req   = $encode->($data, $charset);

        my %trace;
        my $ans   = $transport->($req, \%trace);

        wantarray or return
            UNIVERSAL::isa($ans, 'XML::LibXML::Node') ? $decode->($ans) : $ans;

        $trace{date}   = localtime $start;
        $trace{start}  = $start;
        $trace{encode_elapse} = $trace{transport_start} - $start;

        UNIVERSAL::isa($ans, 'XML::LibXML::Node')
            or return ($ans, \%trace);

        my $dec = $decode->($ans);
        my $end = time;
        $trace{decode_elapse} = $end - $trace{transport_end};
        $trace{elapse} = $end - $start;

        ($dec, \%trace);
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


sub sender($)
{   my ($self, $args) = @_;

    error __"option 'role' only for readers"  if $args->{role};
    error __"option 'roles' only for readers" if $args->{roles};

    my $envns  = $self->envelopeNS;
    my $allns  = $self->prefixPreferences({}, $args->{prefix_table}, 0);
    $self->prefixPreferences($allns, $args->{prefixes}, 1)
        if $args->{prefixes};

    # Translate header

    my ($header, $hlabels) = $self->writerCreateHeader
      ( $args->{header} || [], $allns
      , $args->{mustUnderstand}, $args->{destination}
      );

    # Translate body (3 options)

    my $style   = $args->{style};
    my $bodydef = $args->{body} || [];

    if($style eq 'rpc-literal')
    {   unshift @$bodydef, $self->writerCreateRpcLiteral($allns);
    }
    elsif($style eq 'rpc-encoded')
    {   unshift @$bodydef, $self->writerCreateRpcEncoded($allns);
    }
    elsif($style ne 'document')
    {   error __x"unknown soap message style `{style}'", style => $style;
    }

    my ($body, $blabels) = $self->writerCreateBody($bodydef, $allns);

    # Translate body faults

    my ($fault, $flabels) = $self->writerCreateFault
      ( $args->{faults} || [], $allns
      , pack_type($envns, 'Fault')
      );

    my @hooks =
      ( ($style eq 'rpc-encoded' ? $self->writerEncstyleHook($allns) : ())
      , $self->writerHook($envns, 'Header', @$header)
      , $self->writerHook($envns, 'Body', @$body, @$fault)
      );

    #
    # Pack everything together in one procedure
    #

    my $envelope = $self->schemas->compile
      ( WRITER => pack_type($envns, 'Envelope')
      , hooks  => \@hooks
      , output_namespaces    => $allns
      , elements_qualified   => 1
      , attributes_qualified => 1
      );

    sub
    {   my ($values, $charset) = ref $_[0] eq 'HASH' ? @_ : ( {@_}, undef);
        my $doc   = XML::LibXML::Document->new('1.0', $charset || 'UTF-8');
        my %copy  = %$values;  # do not destroy the calling hash
        my %data;

        $data{$_}   = delete $copy{$_} for qw/Header Body/;
        $data{Body} ||= {};

        foreach my $label (@$hlabels)
        {   defined $copy{$label} or next;
            error __x"header part {name} specified twice", name => $label
                if defined $data{Header}{$label};
            $data{Header}{$label} ||= delete $copy{$label}
        }

        foreach my $label (@$blabels, @$flabels)
        {   defined $copy{$label} or next;
            error __x"body part {name} specified twice", name => $label
                if defined $data{Body}{$label};
            $data{Body}{$label} ||= delete $copy{$label};
        }

        if(@$blabels==2 && !keys %{$data{Body}} ) # ignore 'Fault'
        {  # even when no params, we fill at least one body element
            $data{Body}{$blabels->[0]} = \%copy;
        }
        elsif(keys %copy)
        {   error __x"call data not used: {blocks}", blocks => [keys %copy];
        }

        $envelope->($doc, \%data);
    };
}


sub writerHook($$@)
{   my ($self, $ns, $local, @do) = @_;
 
   +{ type    => pack_type($ns, $local)
    , replace =>
        sub
        {   my ($doc, $data, $path, $tag) = @_;
            my %data = %$data;
            my @h = @do;
            my @childs;
            while(@h)
            {   my ($k, $c) = (shift @h, shift @h);
                if(my $v = delete $data{$k})
                {    my $g = $c->($doc, $v);
                     push @childs, $g if $g;
                }
            }
            warning __x"unused values {names}", names => [keys %data]
                if keys %data;

            # Body must be present, even empty, Header doesn't
            @childs || $tag =~ m/Body$/ or return ();

            my $node = $doc->createElement($tag);
            $node->appendChild($_) for @childs;
            $node;
        }
    };
}


sub writerEncstyleHook($)
{   my ($self, $allns) = @_;
    my $envns   = $self->envelopeNS;
    my $style_w = $self->schemas->compile
      ( WRITER => pack_type($envns, 'encodingStyle')
      , output_namespaces    => $allns
      , include_namespaces   => 0
      , attributes_qualified => 1
      );
    my $style;

    my $before  = sub
      { my ($doc, $values, $path) = @_;
        ref $values eq 'HASH' or return $values;
        $style = $style_w->($doc, delete $values->{encodingStyle});
        $values;
      };

    my $after = sub
      { my ($doc, $node, $path) = @_;
        $node->addChild($style) if defined $style;
        $node;
      };

   { before => $before, after => $after };
}


sub writerCreateHeader($$$$)
{   my ($self, $header, $allns, $understand, $destination) = @_;
    my (@rules, @hlabels);
    my $schema      = $self->schemas;
    my %destination = ref $destination eq 'ARRAY' ? @$destination : ();

    my %understand  = map { ($_ => 1) }
        ref $understand eq 'ARRAY' ? @$understand
      : defined $understand ? "$understand" : ();

    my @h = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;

        my $code = UNIVERSAL::isa($element,'CODE') ? $element
         : $schema->compile
           ( WRITER => $element
           , output_namespaces  => $allns
           , include_namespaces => 0
           , elements_qualified => 'TOP'
           );

        push @rules, $label => $self->writerHeaderEnv($code, $allns
           , delete $understand{$label}, delete $destination{$label});

        push @hlabels, $label;
    }

    keys %understand
        and error __x"mustUnderstand for unknown header {headers}"
                , headers => [keys %understand];

    keys %destination
        and error __x"actor for unknown header {headers}"
                , headers => [keys %destination];

    (\@rules, \@hlabels);
}


sub writerCreateBody($$)
{   my ($self, $body, $allns) = @_;
    my (@rules, @blabels);
    my $schema = $self->schemas;
    my @b      = @$body;
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;

        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
        : $schema->compile
          ( WRITER => $element
          , output_namespaces  => $allns
          , include_namespaces => 0
          , elements_qualified => 'TOP'
          );

        push @rules, $label => $code;
        push @blabels, $label;
    }

    (\@rules, \@blabels);
}


sub writerCreateRpcLiteral($)
{   my ($self, $allns) = @_;
    my $lit = sub
     { my ($doc, $def) = @_;
       UNIVERSAL::isa($def, 'ARRAY')
           or error __x"rpc style requires compileClient with rpcin parameters";

       my ($code, $data) = @$def;
       $code->($doc, $data);
     };

    (rpc => $lit);
}


sub writerCreateRpcEncoded($)
{   my ($self, $allns) = @_;
    my $lit = sub
     { my ($doc, $def) = @_;
       UNIVERSAL::isa($def, 'ARRAY')
           or error __x"rpc style requires compileClient with rpcin parameters";

       my ($code, $data) = @$def;
       $self->startEncoding(doc => $doc);

       my $top = $code->($self, $doc, $data)
           or return ();

       my ($topns, $toplocal) = ($top->namespaceURI, $top->localName);
       $topns || index($toplocal, ':') >= 0
           or error __x"rpc top element requires namespace";

       $top->setAttribute($allns->{$self->envelopeNS}{prefix}.':encodingStyle'
          , $self->encodingNS);

       my $enc = $self->{enc};

       # add namespaces to top element.  Sorted for reproducible results
       $top->setAttribute("xmlns:$_->{prefix}", $_->{uri})
           for sort {$a->{prefix} cmp $b->{prefix}}
                   values %{$enc->{namespaces}};

       $top;
     };

    (rpc => $lit);
}


sub writerCreateFault($$$)
{   my ($self, $faults, $allns, $faulttype) = @_;
    my (@rules, @flabels);

    my $schema = $self->schemas;
    my $fault  = $schema->compile
      ( WRITER => $faulttype
      , output_namespaces  => $allns
      , include_namespaces => 0
      , elements_qualified => 'TOP'
      );

    my @f      = @$faults;
    while(@f)
    {   my ($label, $type) = splice @f, 0, 2;
        my $details = $schema->compile
          ( WRITER => $type
          , output_namespaces  => $allns
          , include_namespaces => 0
          , elements_qualified => 'TOP'
          );

        my $code = sub
          { my ($doc, $data)  = (shift, shift);
            my %copy = %$data;
            $copy{faultactor} = $self->roleURI($copy{faultactor});
            my $det = delete $copy{detail};
            my @det = !defined $det ? () : ref $det eq 'ARRAY' ? @$det : $det;
            $copy{detail}{$type} = [ map {$details->($doc, $_)} @det ];
            $fault->($doc, \%copy);
          };

        push @rules, $label => $code;
        push @flabels, $label;
    }

    (\@rules, \@flabels);
}

#------------------------------------------------


sub receiver($)
{   my ($self, $args) = @_;

    error __"option 'destination' only for writers"
        if $args->{destination};

    error __"option 'mustUnderstand' only for writers"
        if $args->{understand};

    my $style   = $args->{style};
    my $bodydef = $args->{body} || [];

    $style =~ m/^(?:rpc-literal|rpc-encoded|document)$/
        or error __x"unknown soap message style `{style}'", style => $style;

# roles are not checked (yet)
#   my $roles  = $args->{roles} || $args->{role} || 'ULTIMATE';
#   my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    my $faultdec = $self->readerParseFaults($args->{faults} || []);
    my $header   = $self->readerParseHeader($args->{header} || []);
    my $body     = $self->readerParseBody($bodydef);

    my $envns    = $self->envelopeNS;
    my @hooks    = 
      ( ($style eq 'rpc-encoded' ? $self->readerEncstyleHook : ())
      , $self->readerHook($envns, 'Header', @$header)
      , $self->readerHook($envns, 'Body',   @$body)
      );

    my $envelope = $self->schemas->compile
     ( READER => pack_type($envns, 'Envelope')
     , hooks  => \@hooks
     , anyElement   => 'TAKE_ALL'
     , anyAttribute => 'TAKE_ALL'
     );

    sub
    {   my $xml   = shift;
        my $data  = $envelope->($xml);
        my @pairs = ( %{delete $data->{Header} || {}}
                    , %{delete $data->{Body}   || {}});
        while(@pairs)
        {  my $k       = shift @pairs;
           $data->{$k} = shift @pairs;
        }

        $faultdec->($data);
        $data;
    };
}


sub readerHook($$$@)
{   my ($self, $ns, $local, @do) = @_;
    my %trans = map { ($_->[1] => [ $_->[0], $_->[2] ]) } @do; # we need copies
 
    my $replace = sub
      { my ($xml, $trans, $path, $label) = @_;
        my %h;
        foreach my $child ($xml->childNodes)
        {   next unless $child->isa('XML::LibXML::Element');
            my $type = pack_type $child->namespaceURI, $child->localName;
            if(my $t = $trans{$type})
            {   my $v = $t->[1]->($child);
                $h{$t->[0]} = $v if defined $v;
                next;
            }
            return ($label => $self->replyMustUnderstandFault($type))
                if $child->getAttribute('mustUnderstand') || 0;

            # not decoded right now: rpc
            if(! exists $h{$type}) { $h{$type} = $child }
            elsif(ref $h{$type} eq 'ARRAY') { push @{$h{$type}}, $child }
            else { $h{$type} = [ $h{$type}, $child ] }
        }
        ($label => \%h);
      };

   +{ type    => pack_type($ns, $local)
    , replace => $replace
    };
}


sub readerParseHeader($)
{   my ($self, $header) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @h      = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile(READER => $element, anyElement => 'TAKE_ALL');
        push @rules, [$label, $element, $code];

    }

    \@rules;
}


sub readerParseBody($)
{   my ($self, $body) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @b      = @$body;
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile(READER => $element, anyElement => 'TAKE_ALL');
        push @rules, [$label, $element, $code];
    }

    \@rules;
}


sub readerParseFaults($)
{   my ($self, $faults) = @_;
    sub { shift };
}


sub readerEncstyleHook()
{   my $self     = shift;
    my $envns    = $self->envelopeNS;
    my $style_r = $self->schemas->compile
      (READER => pack_type($envns, 'encodingStyle'));  # is attribute

    my $encstyle;  # yes, closures!

    my $before = sub
      { my ($xml, $path) = @_;
        if(my $attr = $xml->getAttributeNode('encodingStyle'))
        {   $encstyle = $style_r->($attr, $path);
            $xml->removeAttribute('encodingStyle');
        }
        $xml;
      };

   my $after   = sub
      { defined $encstyle or return $_[1];
        my $h = $_[1];
        ref $h eq 'HASH' or $h = { _ => $h };
        $h->{encodingStyle} = $encstyle;
        $h;
      };

   { before => $before, after => $after };
}

#------------------------------------------------


sub startEncoding(@)
{   my ($self, %args) = @_;
    require XML::Compile::SOAP::Encoding;
    $self->_init_encoding(\%args);
}

sub startDecoding(@)
{   my ($self, %args) = @_;
    require XML::Compile::SOAP::Encoding;
    $self->_init_decoding(\%args);
}

#------------------------------------------------


sub roleURI($) { panic "not implemented" }


sub roleAbbreviation($) { panic "not implemented" }


sub replyMustUnderstandFault($) { panic "not implemented" }


1;
