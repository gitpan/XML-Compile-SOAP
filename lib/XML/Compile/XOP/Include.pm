# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::XOP::Include;
use vars '$VERSION';
$VERSION = '2.28';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/:xop10/;
use HTTP::Message            ();
use File::Slurp              qw/read_file write_file/;


use overload '""'     => 'content'
           , fallback => 1;


sub new(@)
{   my ($class, %args) = @_;
    $args{bytes} = \(delete $args{bytes})
        if defined $args{bytes} && ref $args{bytes} ne 'SCALAR';
    bless \%args, $class;
}


sub fromMime($)
{   my ($class, $http) = @_;

    my $cid = $http->header('Content-ID') || 'NONE';
    if($cid !~ s/^\s*\<(.*?)\>\s*$/$1/ )
    {   warning __x"part has illegal Content-ID: `{cid}'", cid => $cid;
        return ();
    }

    $class->new
     ( bytes => $http->decoded_content(ref => 1)
     , cid   => $cid
     , type  => scalar $http->content_type
     );
}


sub cid { shift->{cid} }


sub content(;$)
{   my ($self, $byref) = @_;
    unless($self->{bytes})
    {   my $f     = $self->{file};
        my $bytes = try { read_file $f };
        fault "failed reading XOP file {fn}", fn => $f;
        $self->{bytes} = \$bytes;
    }
    $byref ? $self->{bytes} : ${$self->{bytes}};
}


sub xmlNode($$$$)
{   my ($self, $doc, $path, $tag) = @_;
    my $node = $doc->createElement($tag);
    $node->setNamespace($self->{xmime}, 'xmime', 0);
    $node->setAttributeNS($self->{xmime}, contentType => $self->{type});

    my $include = $node->addChild($doc->createElement('Include'));
    $include->setNamespace($self->{xop}, 'xop', 1);
    $include->setAttribute(href => 'cid:'.$self->{cid});
    $node;
}


sub mimePart(;$)
{   my ($self, $headers) = @_;
    my $mime = HTTP::Message->new($headers);
    $mime->header
      ( Content_Type => $self->{type}
      , Content_Transfer_Encoding => 'binary'
      , Content_ID   => '<'.$self->{cid}.'>'
      );

    $mime->content_ref($self->content(1));
    $mime;
}


sub write($)
{   my ($self, $file) = @_;
    write_file $file, {binmode => ':raw'}, $self->content(1);
}

1;
