# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::Transport::SOAPHTTP;
use vars '$VERSION';
$VERSION = '0.75';

use base 'XML::Compile::Transport';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/SOAP11ENV/;

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();

use XML::LibXML   ();
use Encode;

my $parser = XML::LibXML->new;

# (Microsofts HTTP Extension Framework)
my $http_ext_id = SOAP11ENV;


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->userAgent
     ( $args->{user_agent}
     , keep_alive => (exists $args->{keep_alive} ? $args->{keep_alive} : 1)
     , timeout => ($args->{timeout} || 180)
     );
    $self;
}

#-------------------------------------------


sub userAgent(;$)
{   my ($self, $agent) = (shift, shift);
    return $self->{user_agent} = $agent
        if defined $agent;

    $self->{user_agent}
    ||= LWP::UserAgent->new
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
    my $method   = $args->{method}       || 'POST';
    my $soap     = $args->{soap}         || 'SOAP11';
    my $version  = ref $soap ? $soap->version : $soap;
    my $mpost_id = $args->{mpost_id}     || 42;
    my $mime     = $args->{mime};
    my $action   = $args->{action}       || '';

    my $charset  = $self->charset;
    my $ua       = $self->userAgent;

    # Prepare header

    my $header   = $args->{header}       || HTTP::Headers->new;
    $self->headerAddVersions($header);

    if($version eq 'SOAP11')
    {   $mime  ||= 'text/xml';
        $header->header(Content_Type => qq{$mime; charset="$charset"});
    }
    elsif($version eq 'SOAP12')
    {   $mime  ||= 'application/soap+xml';
        my $sa   = defined $action ? qq{; action="$action"} : '';
        $header->header(Content_Type => qq{$mime; charset="$charset"$action});
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

    my $hook = $args->{hook};

      $hook
    ? sub  # hooked code
      { my $trace = $_[1];
        my $u = encode($charset, $_[0]);
        $request->content($u);
        { use bytes; $request->header('Content-Length' => length $u); }
 
        $trace->{http_request}  = $request;
        $trace->{action}        = $action;
        $trace->{soap_version}  = $version;
        $trace->{server}        = $server;
        $trace->{user_agent}    = $ua;
        $trace->{hooked}        = 1;

        my $response = $hook->($request, $trace)
           or return undef;

        $trace->{http_response} = $response;

          defined $response && $response->content_type =~ m![/+]xml$!i
        ? $response->decoded_content
        : undef;
      }

    : sub  # normal code
      { my $trace = $_[1];
        my $u = encode($charset, $_[0]);
        $request->content($u);
        { use bytes; $request->header('Content-Length' => length $u); }

        $trace->{http_request}  = $request;

        my $response = $ua->request($request)
            or return undef;

        $trace->{http_response} = $response;

          $response->content_type =~ m![/+]xml$!i
        ? $response->decoded_content
        : undef;
      };
}


sub headerAddVersions($)
{   my ($thing, $h) = @_;
    foreach my $pkg ( qw/XML::Compile XML::Compile::SOAP LWP/ )
    {   no strict 'refs';
        my $version = ${"${pkg}::VERSION"} || 'undef';
        (my $field = "X-$pkg-Version") =~ s/\:\:/-/g;
        $h->header($field => $version);
    }
}

1;
