# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP;  #!!!
use vars '$VERSION';
$VERSION = '0.61';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util qw/min first/;
use XML::Compile::Util qw/odd_elements/;


# startEncoding is always implemented, loading this class
# the {enc} settings are temporary; live shorter than the object.
sub _init_encoding($)
{   my ($self, $args) = @_;
    my $doc = $args->{doc};
    $doc && UNIVERSAL::isa($doc, 'XML::LibXML::Document')
        or error __x"encoding required an XML document to work with";

    my $allns = $args->{namespaces}
        or error __x"encoding requires prepared namespace table";

    $self->{enc} = $args;
    $self;
}


sub prefixed($;$)
{   my $self = shift;
    my ($ns, $local) = @_==2 ? @_ : unpack_type $_[0];
    length $ns or return $local;

    my $def  =  $self->{enc}{namespaces}{$ns}
        or error __x"namespace prefix for your {ns} not defined", ns => $ns;

    # not used at compile-time, but now we see we needed it.
    $def->{used}
      or warning __x"explicitly pass namespace {ns} in compileMessage(prefixes)"
            , ns => $ns;

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
{   my ($self, $name, $type, $value) = @_;
    my $enc = $self->{enc};
    my $el  = $enc->{doc}->createElement($name);

    my $typedef = $self->prefixed($self->schemaInstanceNS,'type');
    $el->setAttribute($typedef, $self->prefixed($type));

    unless(UNIVERSAL::isa($value, 'XML::LibXML::Element'))
    {   my $write = $self->{writer}{$type} ||= $self->schemas->compile
         ( WRITER => $type
         , output_namespaces  => $enc->{namespaces}
         , include_namespaces => 0
         );
        $value = $write->($enc->{doc}, $value);
    }

    $el->addChild($value);
    $el;
}


sub element($$$)
{   my ($self, $name, $type, $value) = @_;
    my $enc = $self->{enc};
    my $el  = $enc->{doc}->createElement($name);

    unless(UNIVERSAL::isa($value, 'XML::LibXML::Element'))
    {   my $write = $self->{writer}{$type} ||= $self->schemas->compile
         ( WRITER => $type
         , output_namespaces  => $enc->{namespaces}
         , include_namespaces => 0
         );
        $value = $write->($enc->{doc}, $value);
    }

    $el->addChild($value);
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
    $el->setAttribute($self->prefixed($encns, 'arrayType'), $type);

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

    my $r = $opts->{reader_opts} || {};
    $r->{anyElement}   ||= 'TAKE_ALL';
    $r->{anyAttribute} ||= 'TAKE_ALL';

    push @{$r->{hooks}},
      { type    => pack_type($self->encodingNS, 'Array')
      , replace => sub { $self->_dec_array_hook(@_) }
      };

    $self->{dec} = {reader_opts => [%$r], simplify => $opts->{simplify}};
    $self;
}


sub dec(@)
{   my $self  = shift;
    $self->{dec}{href}  = [];
    $self->{dec}{index} = {};
    my $data  = $self->_dec(\@_);

    my $index = $self->{dec}{index};
    $self->_dec_resolve_hrefs($index);

    $data = $self->decSimplify($data)
        if $self->{dec}{simplify};

    wantarray ? ($data, $index) : $data;
}

sub _dec_reader($@)
{   my ($self, $type) = @_;
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

        my $href = $node->getAttribute('href') || '';
        if($href =~ s/^#//)
        {   $$place = undef;
            $self->_dec_href($node, $href, $place);
            next;
        }

        if($ns ne $encns)
        {   my $typedef = $node->getAttributeNS($self->schemaInstanceNS,'type');
            $typedef  ||= $basetype;
            if($typedef)
            {   $$place = $self->_dec_typed($node, $typedef);
                next;
            }

            $$place = $self->_dec_other($node);
            next;
        }

        my $local = $node->localName;
        if($local eq 'Array')
        {   $$place = $self->_dec_other($node);
            next;
        }

        $$place = $self->_dec_soapenc($node, pack_type($ns, $local));
    }

    $self->_dec_index($_->{id} => $_)
        for grep {ref $_ eq 'HASH' && defined $_->{id}} @res;

    \@res;
}

sub _dec_index($$) { $_[0]->{dec}{index}{$_[1]} = $_[2] }

sub _dec_typed($$$)
{   my ($self, $node, $type, $index) = @_;

    my ($prefix, $local) = $type =~ m/(.*?)\:(.*)/ ? ($1, $2) : ('', $type);
    my $ns   = length $prefix ? $node->lookupNamespaceURI($prefix) : '';
    my $full = pack_type $ns, $local;

    my $read = $self->_dec_reader($full)
        or return $node;

    my $data = $read->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $full;
    $data;
}

sub _dec_other($)
{   my ($self, $node) = @_;
    my $ns    = $node->namespaceURI || '';
    my $local = $node->localName;

    my $type = pack_type $ns, $local;
    my $read = $self->_dec_reader($type)
        or return $node;

    my $data = $read->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_NAME} = $type;

    if(my $id = $node->getAttribute('id'))
    {   $self->_dec_index($id => $data);
        $data->{id} = $id;
    }
    $data;
}

sub _dec_soapenc($$)
{   my ($self, $node, $type) = @_;
    my $read = $self->_dec_reader($type)
       or return $node;
    my $data = ($read->($node))[1];
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $type;
    $data;
}

sub _dec_href($$$)
{   my ($self, $node, $to, $where) = @_;
    my $data;
    push @{$self->{dec}{href}}, $to => $where;
}

sub _dec_resolve_hrefs($)
{   my ($self, $index) = @_;
    my $hrefs = $self->{dec}{href};

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

    my ($basetype, $dims) = ($1, $2);
    my @dims = split /\,/, $dims;

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
    $self->_dec_simple($tree, \%opts);
}

sub _dec_simple($$)
{   my ($self, $tree, $opts) = @_;

    ref $tree
        or return $tree;

    if(ref $tree eq 'ARRAY')
    {   my @a = map { $self->_dec_simple($_, $opts) } @$tree;
        return @a==1 ? $a[0] : \@a;
    }

    ref $tree eq 'HASH'
        or return $tree;

    my %h;
    while(my ($k, $v) = each %$tree)
    {   next if $k =~ m/^(?:_NAME$|_TYPE$|id$|\{)/;
        $h{$k} = ref $v ? $self->_dec_simple($v, $opts) : $v;
    }
    keys(%h)==1 && exists $h{_} ? $h{_} : \%h;
}

1;
