# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use warnings;
use strict;

package XML::Compile::SOAP;  #!!!
use vars '$VERSION';
$VERSION = '0.71';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util qw/min first/;
use XML::Compile::Util qw/odd_elements SCHEMA2001 unpack_type/;


# startEncoding is always implemented, loading this class
# the {enc} settings are temporary; live shorter than the object.
sub _init_encoding($)
{   my ($self, $args) = @_;
    my $doc = $args->{doc};
    $doc && UNIVERSAL::isa($doc, 'XML::LibXML::Document')
        or error __x"encoding required an XML document to work with";

    my $ns = $args->{namespaces} || {};
    if(ref $ns eq 'ARRAY')
    {   my @ns = @$ns;
        $ns    = {};
        while(@ns)
        {   my ($prefix, $uri) = (shift @ns, shift @ns);
            $ns->{$uri} = {uri => $uri, prefix => $prefix};
        }
    }

    $args->{namespaces} = $ns;
    $self->{enc} = $args;

    $self->encAddNamespaces
      ( xsd => $self->schemaNS
      , xsi => $self->schemaInstanceNS
      );

    $self;
}


sub encAddNamespaces(@)
{   my $ns = shift->{enc}{namespaces};
    while(@_)
    {   my ($prefix, $uri) = (shift, shift);
        $ns->{$uri} = {uri => $uri, prefix => $prefix};
    }
    $ns;
}

sub encAddNamespace(@) { shift->encAddNamespaces(@_) }


sub prefixed($;$)
{   my $self = shift;
    my ($ns, $local) = @_==2 ? @_ : unpack_type $_[0];
    length $ns or return $local;

    my $def  =  $self->{enc}{namespaces}{$ns}
        or error __x"namespace prefix for your {ns} not defined", ns => $ns;

    $def->{prefix}.':'.$local;
}


sub enc($$$)
{   my ($self, $local, $value, $id) = @_;
    my $enc   = $self->{enc};
    my $type  = pack_type $self->encodingNS, $local;

    my $write = $self->{writer}{$type} ||= $self->schemas->compile
      ( WRITER => $type
      , output_namespaces  => $enc->{namespaces}
      , elements_qualified => 1
      , include_namespaces => 0
      );

    $write->($enc->{doc}, {_ => $value, id => $id} );
}


sub typed($$$)
{   my ($self, $type, $name, $value) = @_;
    my $enc = $self->{enc};
    my $doc = $enc->{doc};

    my $showtype;
    if($type =~ s/^\{\}//)
    {   $showtype = $type;
    }
    else
    {   my ($tns, $tlocal) = unpack_type $type;
        unless(length $tns)
        {   $tns = $self->schemaNS;
            $type = pack_type $tns, $tlocal;
        }
        $showtype = $self->prefixed($tns, $tlocal);
    }

    my $el = $self->element($type, $name, $value);
    my $typedef = $self->prefixed($self->schemaInstanceNS, 'type');
    $el->setAttribute($typedef, $showtype);
    $el;
}


sub struct($@)
{   my ($self, $type, @childs) = @_;
    my $typedef = $self->prefixed($type);
    my $doc     = $self->{enc}{doc};
    my $struct  = $doc->createElement($typedef);
    $struct->addChild($_) for @childs;
    $struct;
}


sub element($$$)
{   my ($self, $type, $name, $value) = @_;

    return $value
        if UNIVERSAL::isa($value, 'XML::LibXML::Element');

    my $enc = $self->{enc};
    my $doc = $enc->{doc};

    $type = pack_type $self->schemaNS, $type   # make absolute
        if $type !~ m/^\{/;

    my $el  = $doc->createElement($name);
    my $write = $self->{writer}{$type} ||= $self->schemas->compile
      ( WRITER => $type
      , output_namespaces  => $enc->{namespaces}
      , include_namespaces => 0
      );

    $value = $write->($doc, $value);
    $el->addChild($value) if defined $value;
    $el;
}


my $id_count = 0;
sub href($$$)
{   my ($self, $name, $to, $prefid) = @_;
    my $id  = $to->getAttribute('id');
    unless(defined $id)
    {   $id = defined $prefid ? $prefid : 'id-'.++$id_count;
        $to->setAttribute(id => $id);
    }

    my $ename = $self->prefixed($name);
    my $el  = $self->{enc}{doc}->createElement($ename);
    $el->setAttribute(href => "#$id");
    $el;
}


sub nil($;$)
{   my $self = shift;
    my ($type, $name) = @_==2 ? @_ : (undef, $_[0]);
    my ($ns, $local) = unpack_type $name;

    my $doc  = $self->{enc}{doc};
    my $el
      = $ns
      ? $doc->createElementNS($ns, $local)
      : $doc->createElement($local);

    my $xsi = $self->schemaInstanceNS;
    $el->setAttribute($self->prefixed($xsi, 'nil'), 'true');

    $el->setAttribute($self->prefixed($xsi, 'type'), $self->prefixed($type))
       if $type;

    $el;
}


sub array($$$@)
{   my ($self, $name, $itemtype, $array, %opts) = @_;

    my $encns   = $self->encodingNS;
    my $enc     = $self->{enc};
    my $doc     = $enc->{doc};

    my $offset  = $opts{offset} || 0;
    my $slice   = $opts{slice};

    my ($min, $size) = ($offset, scalar @$array);
    $min++ while $min <= $size && !defined $array->[$min];

    my $max = defined $slice && $min+$slice-1 < $size ? $min+$slice-1 : $size;
    $max-- while $min <= $max && !defined $array->[$max];

    my $sparse = 0;
    for(my $i = $min; $i < $max; $i++)
    {   next if defined $array->[$i];
        $sparse = 1;
        last;
    }

    my $elname = $self->prefixed(defined $name ? $name : ($encns, 'Array'));
    my $el     = $doc->createElement($elname);
    my $nested = $opts{nested_array} || '';
    my $type   = $self->prefixed($itemtype)."$nested\[$size]";

    $el->setAttribute(id => $opts{id}) if defined $opts{id};
    my $at     = $opts{array_type} ? $opts{arrayType} 
               : $self->prefixed($encns, 'arrayType');
    $el->setAttribute($at, $type) if defined $at;

    if($sparse)
    {   my $placeition = $self->prefixed($encns, 'position');
        for(my $r = $min; $r <= $max; $r++)
        {   my $row  = $array->[$r] or next;
            my $node = $row->cloneNode(1);
            $node->setAttribute($placeition, "[$r]");
            $el->addChild($node);
        }
    }
    else
    {   $el->setAttribute($self->prefixed($encns, 'offset'), "[$min]")
            if $min > 0;
        $el->addChild($array->[$_]) for $min..$max;
    }

    $el;
}


sub multidim($$$@)
{   my ($self, $name, $itemtype, $array, %opts) = @_;
    my $encns   = $self->encodingNS;
    my $enc     = $self->{enc};
    my $doc     = $enc->{doc};

    # determine dimensions
    my @dims;
    for(my $dim = $array; ref $dim eq 'ARRAY'; $dim = $dim->[0])
    {   push @dims, scalar @$dim;
    }

    my $sparse = $self->_check_multidim($array, \@dims, '');
    my $elname = $self->prefixed(defined $name ? $name : ($encns, 'Array'));
    my $el     = $doc->createElement($elname);
    my $type   = $self->prefixed($itemtype) . '['.join(',', @dims).']';

    $el->setAttribute(id => $opts{id}) if defined $opts{id};
    $el->setAttribute($self->prefixed($encns, 'arrayType'), $type);

    my @data   = $self->_flatten_multidim($array, \@dims, '');
    if($sparse)
    {   my $placeition = $self->prefixed($encns, 'position');
        while(@data)
        {   my ($place, $field) = (shift @data, shift @data);
            my $node = $field->cloneNode(1);
            $node->setAttribute($placeition, "[$place]");
            $el->addChild($node);
        }
    }
    else
    {   $el->addChild($_) for odd_elements @data;
    }

    $el;
}

sub _check_multidim($$$)
{   my ($self, $array, $dims, $loc) = @_;
    my @dims = @$dims;

    my $expected = shift @dims;
    @$array <= $expected
       or error __x"dimension at ({location}) is {size}, larger than size {expect} of first row"
           , location => $loc, size => scalar(@$array), expect => $expected;

    my $sparse = 0;
    foreach (my $x = 0; $x < $expected; $x++)
    {   my $el   = $array->[$x];
        my $cell = length $loc ? "$loc,$x" : $x;

        if(!defined $el) { $sparse++ }
        elsif(@dims==0)   # bottom level
        {   UNIVERSAL::isa($el, 'XML::LibXML::Element')
               or error __x"array element at ({location}) shall be a XML element or undef, is {value}"
                    , location => $cell, value => $el;
        }
        elsif(ref $el eq 'ARRAY')
        {   $sparse += $self->_check_multidim($el, \@dims, $cell);
        }
        else
        {   error __x"array at ({location}) expects ARRAY reference, is {value}"
               , location => $cell, value => $el;
        }
    }

    $sparse;
}

sub _flatten_multidim($$$)
{   my ($self, $array, $dims, $loc) = @_;
    my @dims = @$dims;

    my $expected = shift @dims;
    my @data;
    foreach (my $x = 0; $x < $expected; $x++)
    {   my $el = $array->[$x];
        defined $el or next;

        my $cell = length $loc ? "$loc,$x" : $x;
        push @data, @dims==0 ? ($cell, $el)  # deepest dim
         : $self->_flatten_multidim($el, \@dims, $cell);
    }

    @data;
}

#--------------------------------------------------


sub _init_decoding($)
{   my ($self, $opts) = @_;

    my %r =  $opts->{reader_opts} ? %{$opts->{reader_opts}} : ();
    $r{anyElement}   ||= 'TAKE_ALL';
    $r{anyAttribute} ||= 'TAKE_ALL';
    $r{permit_href}    = 1;

    push @{$r{hooks}},
     { type    => pack_type($self->encodingNS, 'Array')
     , replace => sub { $self->_dec_array_hook(@_) }
     };

    $self->{dec} =
     { reader_opts => [%r]
     , simplify    => $opts->{simplify}
     };

    $self;
}


sub dec(@)
{   my $self  = shift;
    my $data  = $self->_dec( [@_] );
 
    my ($index, $hrefs) = ({}, []);
    $self->_dec_find_ids_hrefs($index, $hrefs, \$data);
    $self->_dec_resolve_hrefs ($index, $hrefs);

    $data = $self->decSimplify($data)
        if $self->{dec}{simplify};

    ref $data eq 'ARRAY'
        or return $data;

    # find the root element
    my $encns = $self->encodingNS;
    my @roots;
    for(my $i = 0; $i < @_ && $i < @$data; $i++)
    {   my $root = $_[$i]->getAttributeNS($encns, 'root');
        push @roots, $data->[$i] if !defined $root || $root!=0;
    }

    my $answer
      = !@roots        ? $data
      : @$data==@roots ? $data
      : @roots==1      ? $roots[0]
      : \@roots;

    $answer;
}

sub _dec_reader($@)
{   my ($self, $type) = @_;
    return $self->{dec}{$type} if $self->{dec}{$type};

    my ($typens, $typelocal) = unpack_type $type;
    my $schemans  = $self->schemaNS;

    if(   $typens ne $schemans
       && !$self->schemas->namespaces->find(element => $type))
    {   # work-around missing element
        $self->schemas->importDefinitions(<<__FAKE_SCHEMA);
<schema xmlns="$schemans" targetNamespace="$typens" xmlns:d="$typens">
<element name="$typelocal" type="d:$typelocal" />
</schema>
__FAKE_SCHEMA
    }

    $self->{dec}{$type} ||= $self->schemas->compile
      (READER => $type, @{$self->{dec}{reader_opts}}, @_);
}

sub _dec($;$$$)
{   my ($self, $nodes, $basetype, $offset, $dims) = @_;
    my $encns = $self->encodingNS;

    my @res;
    $#res = $offset-1 if defined $offset;

    foreach my $node (@$nodes)
    {   my $ns    = $node->namespaceURI || '';
        my $place;
        if($dims)
        {   my $pos = $node->getAttributeNS($encns, 'position');
            if($pos && $pos =~ m/^\[([\d,]+)\]/ )
            {   my @pos = split /\,/, $1;
                $place  = \$res[shift @pos];
                $place  = \(($$place ||= [])->[shift @pos]) while @pos;
            }
        }

        unless($place)
        {   push @res, undef;
            $place = \$res[-1];
        }

        if(my $href = $node->getAttribute('href') || '')
        {   $$place = { href => $href };
            next;
        }

        if($ns ne $encns)
        {   my $typedef = $node->getAttributeNS($self->schemaInstanceNS,'type');
            if($typedef)
            {   $$place = $self->_dec_typed($node, $typedef);
                next;
            }

            $$place = $self->_dec_other($node, $basetype);
            next;
        }

        my $local = $node->localName;
        if($local eq 'Array')
        {   $$place = $self->_dec_other($node, $basetype);
            next;
        }

        $$place = $self->_dec_soapenc($node, pack_type($ns, $local));
    }

    \@res;
}

sub _dec_typed($$$)
{   my ($self, $node, $type, $index) = @_;

    my ($prefix, $local) = $type =~ m/^(.*?)\:(.*)/ ? ($1, $2) : ('',$type);
    my $ns   = length $prefix ? $node->lookupNamespaceURI($prefix) : '';
    my $full = pack_type $ns, $local;

    my $read = $self->_dec_reader($full)
        or return $node;

    my $child = $read->($node);
    my $data  = ref $child eq 'HASH' ? $child : { _ => $child };
    $data->{_TYPE} = $full;
    $data->{_NAME} = pack_type $node->namespaceURI, $node->localName;

    my $id = $node->getAttribute('id');
    $data->{id} = $id if defined $id;

    { $local => $data };
}

sub _dec_other($$)
{   my ($self, $node, $basetype) = @_;
    my $local = $node->localName;
    my $ns    = $node->namespaceURI || '';
    my $elem  = pack_type $ns, $local;

    my $data;

    my $type  = $basetype || $elem;
    my $read  = try { $self->_dec_reader($type) };
    if($@)
    {    # warn $@->wasFatal->message;  #--> element not found
         # Element not known, so we must autodetect the type
         my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
         if(@childs)
         {   my ($childbase, $dims);
             if($type =~ m/(.+?)\s*\[([\d,]+)\]$/)
             {   $childbase = $1;
                 $dims = ($2 =~ tr/,//) + 1;
             }
             my $dec_childs =  $self->_dec(\@childs, $childbase, 0, $dims);
             $local = '_' if $local eq 'Array';  # simplifies better
             $data  = { $local => $dec_childs } if $dec_childs;
         }
         else
         {   $data->{$local} = $node->textContent;
             $data->{_TYPE}  = $basetype if $basetype;
         }
    }
    else
    {    $data = $read->($node);
         $data = { _ => $data } if ref $data ne 'HASH';
         $data->{_TYPE} = $basetype if $basetype;
    }

    $data->{_NAME} = $elem;

    my $id = $node->getAttribute('id');
    $data->{id} = $id if defined $id;

    $data;
}

sub _dec_soapenc($$)
{   my ($self, $node, $type) = @_;
    my $read = $self->_dec_reader($type)
       or return $node;
    my $data = $read->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $type;
    $data;
}

sub _dec_find_ids_hrefs($$$)
{   my ($self, $index, $hrefs, $node) = @_;
    ref $$node or return;

    if(ref $$node eq 'ARRAY')
    {   foreach my $child (@$$node)
        {   $self->_dec_find_ids_hrefs($index, $hrefs, \$child);
        }
    }
    elsif(ref $$node eq 'HASH')
    {   $index->{$$node->{id}} = $$node
            if defined $$node->{id};

        if(my $href = $$node->{href})
        {   push @$hrefs, $href => $node if $href =~ s/^#//;
        }

        foreach my $k (keys %$$node)
        {   $self->_dec_find_ids_hrefs($index, $hrefs, \( $$node->{$k} ));
        }
    }
    elsif(UNIVERSAL::isa($$node, 'XML::LibXML::Element'))
    {   my $search = XML::LibXML::XPathContext->new($$node);
        $index->{$_->value} = $_->getOwnerElement
            for $search->findnodes('.//@id');

        # we cannot restore deep hrefs, so only top level
        if(my $href = $$node->getAttribute('href'))
        {   push @$hrefs, $href => $node if $href =~ s/^#//;
        }
    }
}

sub _dec_resolve_hrefs($$)
{   my ($self, $index, $hrefs) = @_;

    while(@$hrefs)
    {   my ($to, $where) = (shift @$hrefs, shift @$hrefs);
        my $dest = $index->{$to};
        unless($dest)
        {   warning __x"cannot find id for href {name}", name => $to;
            next;
        }
        $$where = $dest;
    }
}

sub _dec_array_hook($$$)
{   my ($self, $node, $args, $where, $local) = @_;

    my $at = $node->getAttributeNS($self->encodingNS, 'arrayType')
        or return $node;

    $at =~ m/^(.*) \s* \[ ([\d,]+) \] $/x
        or return $node;

    my ($preftype, $dims) = ($1, $2);
    my @dims = split /\,/, $dims;
   
    my $basetype;
    if(index($preftype, ':') >= 0)
    {   my ($prefix, $local) = split /\:/, $preftype;
        $basetype = pack_type $node->lookupNamespaceURI($prefix), $local;
    }
    else
    {   $basetype = pack_type '', $preftype;
    }

    return $self->_dec_array_one($node, $basetype, $dims[0])
        if @dims == 1;

     my $first = first {$_->isa('XML::LibXML::Element')} $node->childNodes;

       $first && $first->getAttributeNS($self->encodingNS, 'position')
     ? $self->_dec_array_multisparse($node, $basetype, \@dims)
     : $self->_dec_array_multi($node, $basetype, \@dims);
}

sub _dec_array_one($$$)
{   my ($self, $node, $basetype, $size) = @_;

    my $off    = $node->getAttributeNS($self->encodingNS, 'offset') || '[0]';
    $off =~ m/^\[(\d+)\]$/ or return $node;

    my $offset = $1;
    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    my $array  = $self->_dec(\@childs, $basetype, $offset, 1);
    $#$array   = $size -1;   # resize array to specified size
    $array;
}

sub _dec_array_multisparse($$$)
{   my ($self, $node, $basetype, $dims) = @_;

    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    my $array  = $self->_dec(\@childs, $basetype, 0, scalar(@$dims));
    $array;
}

sub _dec_array_multi($$$)
{   my ($self, $node, $basetype, $dims) = @_;

    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    $self->_dec_array_multi_slice(\@childs, $basetype, $dims);
}

sub _dec_array_multi_slice($$$)
{   my ($self, $childs, $basetype, $dims) = @_;
    if(@$dims==1)
    {   my @col = splice @$childs, 0, $dims->[0];
        return $self->_dec(\@col, $basetype);
    }
    my ($rows, @dims) = @$dims;

    [ map { $self->_dec_array_multi_slice($childs, $basetype, \@dims) }
        1..$rows ]
}


sub decSimplify($@)
{   my ($self, $tree, %opts) = @_;
    defined $tree or return ();
    $self->{dec}{_simple_recurse} = {};
    $self->_dec_simple($tree, \%opts);
}

sub _dec_simple($$)
{   my ($self, $tree, $opts) = @_;

    ref $tree
        or return $tree;

    return $tree
        if $self->{dec}{_simple_recurse}{$tree};

    $self->{dec}{_simple_recurse}{$tree}++;

    if(ref $tree eq 'ARRAY')
    {   my @a = map { $self->_dec_simple($_, $opts) } @$tree;
        return $a[0] if @a==1;

        # array of hash with each one element becomes hash
        my %out;
        foreach my $hash (@a)
        {   ref $hash eq 'HASH' && keys %$hash==1
                or return \@a;

            my ($name, $value) = each %$hash;
            if(!exists $out{$name}) { $out{$name} = $value }
            elsif(ref $out{$name} eq 'ARRAY')
            {   $out{$name} = [ $out{$name} ]   # array of array: keep []
                    if ref $out{$name}[0] ne 'ARRAY' && ref $value eq 'ARRAY';
                push @{$out{$name}}, $value;
            }
            else { $out{$name} = [ $out{$name}, $value ] }
        }
        return \%out;
    }

    ref $tree eq 'HASH'
        or return $tree;

    foreach my $k (keys %$tree)
    {   if($k =~ m/^(?:_NAME$|_TYPE$|id$|\{)/) { delete $tree->{$k} }
        elsif(ref $tree->{$k})
        {   $tree->{$k} = $self->_dec_simple($tree->{$k}, $opts);
        }
    }

    delete $self->{dec}{_simple_recurse}{$tree};

    keys(%$tree)==1 && exists $tree->{_} ? $tree->{_} : $tree;
}

1;
