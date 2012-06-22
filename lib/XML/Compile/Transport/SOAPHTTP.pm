# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::Transport::SOAPHTTP;
use vars '$VERSION';
$VERSION = '2.27';

use base 'XML::Compile::Transport';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/SOAP11ENV SOAP11HTTP/;
use XML::Compile   ();

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();

if($] >= 5.008003)
{   use Encode;
    Encode->import;
}
else
{   *encode = sub { $_[1] };
}

# (Microsofts HTTP Extension Framework)
my $http_ext_id = SOAP11ENV;

__PACKAGE__->register(SOAP11HTTP);


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->userAgent
      ( $args->{user_agent}
      , keep_alive => (exists $args->{keep_alive} ? $args->{keep_alive} : 1)
      , timeout    => ($args->{timeout} || 180)
      );
    $self;
}

sub initWSDL11($)
{   my ($class, $wsdl) = @_;
    trace "initialize SOAPHTTP transporter for WSDL11";
}

#-------------------------------------------


sub userAgent(;$)
{   my ($self, $agent) = (shift, shift);
    return $self->{user_agent} = $agent
        if defined $agent;

    $self->{user_agent} ||= LWP::UserAgent->new
      ( requests_redirectable => [ qw/GET HEAD POST M-POST/ ]
      , parse_head => 0
      , protocols_allowed => [ qw/http https/ ]
      , @_
      );
}

#-------------------------------------------


# SUPER::compileClient() calls this method to do the real work
sub _prepare_call($)
{   my ($self, $args) = @_;
    my $method   = $args->{method}   || 'POST';
    my $soap     = $args->{soap}     || 'SOAP11';
    my $version  = ref $soap ? $soap->version : $soap;
    my $mpost_id = $args->{mpost_id} || 42;
    my $action   = $args->{action};
    my $mime     = $args->{mime};
    my $kind     = $args->{kind}     || 'request-response';
    my $expect   = $kind ne 'one-way' && $kind ne 'notification-operation';

    my $charset  = $self->charset;
    my $ua       = $self->userAgent;

    # Prepare header
    my $header   = $args->{header}   || HTTP::Headers->new;
    $self->headerAddVersions($header);

    my $content_type;
    if($version eq 'SOAP11')
    {   $mime  ||= 'text/xml';
        $content_type = qq{$mime; charset="$charset"};
    }
    elsif($version eq 'SOAP12')
    {   $mime  ||= 'application/soap+xml';
        my $sa   = defined $action ? qq{; action="$action"} : '';
        $content_type = qq{$mime; charset="$charset"$sa};
        $header->header(Accept => $mime);  # not the HTML answer
    }
    else
    {   error "SOAP version {version} not implemented", version => $version;
    }

    if($method eq 'POST')
    {   $header->header(SOAPAction => qq{"$action"})
            if defined $action;
    }
    elsif($method eq 'M-POST')
    {   $header->header(Man => qq{"$http_ext_id"; ns=$mpost_id});
        $header->header("$mpost_id-SOAPAction", qq{"$action"})
            if $version eq 'SOAP11';
    }
    else
    {   error "SOAP method must be POST or M-POST, not {method}"
          , method => $method;
    }

    # Prepare request

    # Ideally, we should change server when one fails, and stick to that
    # one as long as possible.
    my $server  = $self->address;
    my $request = HTTP::Request->new($method => $server, $header);
    $request->protocol('HTTP/1.1');

    # Create handler

    my ($create_message, $parse_message)
      = exists $INC{'XML/Compile/XOP.pm'}
      ? $self->_prepare_xop_call($content_type)
      : $self->_prepare_simple_call($content_type);

    $parse_message = $self->_prepare_for_no_answer($parse_message)
        unless $expect;

    my $hook = $args->{hook};

    $hook
    ? sub  # hooked code
      { my $trace = $_[1];
        $create_message->($request, $_[0], $_[2]);
 
        $trace->{http_request}  = $request;
        $trace->{action}        = $action;
        $trace->{soap_version}  = $version;
        $trace->{server}        = $server;
        $trace->{user_agent}    = $ua;
        $trace->{hooked}        = 1;

        my $response = $hook->($request, $trace, $self)
            or return undef;

        $trace->{http_response} = $response;
        if($response->is_error)
        {   error $response->message
                if $response->header('Client-Warning');

            warning $response->message;
            # still try to parse the response for Fault blocks
        }

        $parse_message->($response);
      }

    : sub  # real call
      { my $trace = $_[1];
        $create_message->($request, $_[0], $_[2]);

        $trace->{http_request}  = $request;

#warn $request->as_string;
        my $response = $ua->request($request)
            or return undef;

        $trace->{http_response} = $response;

        if($response->is_error)
        {   error $response->message
                if $response->header('Client-Warning');

            warning $response->message;
            # still try to parse the response for Fault blocks
        }

        $parse_message->($response);
      };
}

sub _prepare_simple_call($)
{   my ($self, $content_type) = @_;

    my $create = sub
      { my ($request, $content) = @_;
        $request->header(Content_Type => $content_type);
        $request->content_ref($content);   # already bytes (not utf-8)
        use bytes; $request->header('Content-Length' => length $$content);
      };

    my $parse  = sub
      { my $response = shift;
        UNIVERSAL::isa($response, 'HTTP::Response')
            or error __x"no response object received";

        my $ct       = $response->content_type || '';

        lc($ct) ne 'multipart/related'
            or error __x"remote system uses XOP, use XML::Compile::XOP";
        
        info "received ".$response->status_line;

        $ct =~ m,[/+]xml$,i
            or error __x"answer is not xml but `{type}'", type => $ct;

        # HTTP::Message::decoded_content() does not work for old Perls
        my $content = $] >= 5.008 ? $response->decoded_content(ref => 1)
          : $response->content(ref => 1);

        ($content, {});
      };

    ($create, $parse);
}

sub _prepare_xop_call($)
{   my ($self, $content_type) = @_;
    my ($simple_create, $simple_parse)
      = $self->_prepare_simple_call($content_type);

    my $charset = $self->charset;
    my $create  = sub
      { my ($request, $content, $mtom) = @_;
        $mtom        ||= [];
        @$mtom or return $simple_create->($request, $content);

        my $bound      = "MIME-boundary-".int rand 10000;
        (my $start_cid = $mtom->[0]->cid) =~ s/^.*\@/xml@/;

        $request->header(Content_Type => <<_CT);
multipart/related;
 boundary="$bound";
 type="application/xop+xml"
 start="<$start_cid>";
 start-info="text/xml"
_CT

        my $base = HTTP::Message->new
          ( [ Content_Type => <<_CT
application/xop+xml;
 charset="$charset"; type="text/xml"
_CT
            , Content_Transfer_Encoding => '8bit'
            , Content_ID  => '<'.$start_cid.'>'
            ] );
        $base->content_ref($content);   # already bytes (not utf-8)

        my @parts = ($base, map { $_->mimePart } @$mtom);
        $request->parts(@parts); #$base, map { $_->mimePart } @$mtom);
        $request;
      };

    my $parse  = sub
      { my ($response, $mtom) = @_;
        my $ct = $response->header('Content-Type') || '';
        $ct    =~ m!^\s*multipart/related\s*\;!
             or return $simple_parse->($response);

        my %parts;
        foreach my $part ($response->parts)
        {   my $include = XML::Compile::XOP::Include->fromMime($part)
               or next;
            $parts{$include->cid} = $include;
        }

        if($ct !~ m!start\=(["']?)\<([^"']*)\>\1!)
        {   warning __x"cannot find root node in content-type `{ct}'", ct=>$ct;
            return ();
        }

        my $startid = $2;
        my $root = delete $parts{$startid};
        unless(defined $root)
        {   warning __x"cannot find root node id in parts `{id}'",id=>$startid;
            return ();
        }

        ($root->content(1), \%parts);
      };

    ($create, $parse);
}

sub _prepare_for_no_answer($)
{   my $self = shift;
    sub
      { my $response = shift;
        my $ct       = $response->content_type || '';

        info "received ".$response->status_line;

        my $content = '';
        if($ct =~ m,[/+]xml$,i)
        {   # HTTP::Message::decoded_content() does not work for old Perls
            $content = $] >= 5.008 ? $response->decoded_content(ref => 1)
              : $response->content(ref => 1);
        }

        ($content, {});
      };
}


sub headerAddVersions($)
{   my ($thing, $h) = @_;
    foreach my $pkg (qw/XML::Compile XML::Compile::Cache
       XML::Compile::SOAP XML::LibXML LWP/)
    {   no strict 'refs';
        my $version = ${"${pkg}::VERSION"} || 'undef';
        (my $field = "X-$pkg-Version") =~ s/\:\:/-/g;
        $h->header($field => $version);
    }
}

1;
