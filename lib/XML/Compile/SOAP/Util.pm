# Copyrights 2007-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Util;
use vars '$VERSION';
$VERSION = '2.03';

use base 'Exporter';

my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP WSDL11SOAP/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;
my @http   = qw/SOAP11HTTP WSDL11HTTP SOAP11ENV/;
my @daemon = qw/MSEXT/;

our @EXPORT_OK = (@soap11, @wsdl11, @http, @daemon);
our %EXPORT_TAGS =
  ( soap11 => \@soap11
  , wsdl11 => \@wsdl11
  , http   => \@http
  , daemon => \@daemon
  );


use constant SOAP11         => 'http://schemas.xmlsoap.org/soap/';
use constant SOAP11ENV      => SOAP11. 'envelope/';
use constant SOAP11ENC      => SOAP11. 'encoding/';
use constant SOAP11NEXT     => SOAP11. 'actor/next';
use constant SOAP11HTTP     => SOAP11. 'http';


use constant WSDL11         => 'http://schemas.xmlsoap.org/wsdl/';
use constant WSDL11SOAP     => WSDL11. 'soap/';
use constant WSDL11HTTP     => WSDL11. 'http/';
use constant WSDL11MIME     => WSDL11. 'mime/';
use constant WSDL11SOAP12   => WSDL11. 'soap12/';
 

use constant MSEXT          => SOAP11ENV;

1;
