# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP::HTTPClient;
use vars '$VERSION';
$VERSION = '0.56';
use base 'XML::Compile::SOAP::Client';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();

use Time::HiRes   qw/time/;
use XML::LibXML   ();

# (Microsofts HTTP Extension Framework)
my $http_ext_id = 'http://schemas.xmlsoap.org/soap/envelope/';


my $parser;
sub new(@)
{   my ($class, %args) = @_;
    my $ua       = $args{user_agent}   || $class->defaultUserAgent;
    my $method   = $args{method}       || 'POST';
    my $version  = $args{soap_version} || 'SOAP11';
    my $header   = $args{header}       || HTTP::Headers->new;
    my $charset  = $args{charset}      || 'utf-8';
    my $mpost_id = $args{mpost_id}     || 42;
    my $mime     = $args{mime};

    my $action   = $args{action}
        or error __x"soap action not specified";

    my $address  = $args{address};
    unless($address)
    {   $address = $action;
        $address =~ s/\#.*//;
    }
    my @addrs    = ref $address eq 'ARRAY' ? @$address : $address;

    $class->headerAddVersions($header);

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
    {   $header->header(SOAPAction => qq{"$action"}) if defined $action;
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

    # pick random server.  Ideally, we should change server when one
    # fails, and stick to that one as long as possible.
    my $server  = @addrs[rand @addrs];

    my $request = HTTP::Request->new($method => $server, $header);

    if(my $fake_server = $class->fakeServer)
    {   return sub
          { my ($answer, $trace) = $fake_server->
              ( action => $action, message => $_[0], http_header => $request
              , user_agent => $ua, server => $server, soap_version => $version
              , soap => $class->soapClientImplementation($version)
              );
            wantarray ? ($answer, $trace) : $answer;
          }
    }

    $parser   ||= XML::LibXML->new;
    sub
    {   $request->content(ref $_[0] ? $_[0]->toString : $_[0]);
        my $start    = time;
        my $response = $ua->request($request);

        my %trace =
          ( start    => scalar(localtime $start)
          , request  => $request
          , response => $response
          , elapse   => (time - $start)
          );

        my $answer;
        if($response->content_type =~ m![/+]xml$!i)
        {   $answer = eval {$parser->parser_string($response->decoded_content)};
            $trace{error} = $@ if $@;
        }
        else
        {   $trace{error} = 'no xml as answer';
        }

        wantarray ? ($answer, \%trace) : $answer;
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


my $user_agent;
sub defaultUserAgent(;$)
{   my $class = shift;
    return $user_agent = shift if @_;

    $user_agent ||= LWP::UserAgent->new
     ( requests_redirectable => [ qw/GET HEAD POST M-POST/ ]
     );
}


1;
