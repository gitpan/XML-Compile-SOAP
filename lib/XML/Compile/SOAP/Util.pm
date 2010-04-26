# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Util;
use vars '$VERSION';
$VERSION = '2.13';

use base 'Exporter';

my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP WSDL11SOAP/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;
my @http   = qw/SOAP11HTTP WSDL11HTTP SOAP11ENV/;
my @daemon = qw/MSEXT/;
my @xop10  = qw/XOP10 XMIME10 XMIME11/;

our @EXPORT_OK = (@soap11, @wsdl11, @http, @daemon, @xop10);
our %EXPORT_TAGS =
  ( soap11 => \@soap11
  , wsdl11 => \@wsdl11
  , http   => \@http
  , daemon => \@daemon
  , xop10  => \@xop10
  );


use constant SOAP11 => 'http://schemas.xmlsoap.org/soap/';
use constant
  { SOAP11ENV       => SOAP11. 'envelope/'
  , SOAP11ENC       => SOAP11. 'encoding/'
  , SOAP11NEXT      => SOAP11. 'actor/next'
  , SOAP11HTTP      => SOAP11. 'http'
  };


use constant WSDL11 => 'http://schemas.xmlsoap.org/wsdl/';
use constant
  { WSDL11SOAP      => WSDL11. 'soap/'
  , WSDL11HTTP      => WSDL11. 'http/'
  , WSDL11MIME      => WSDL11. 'mime/'
  , WSDL11SOAP12    => WSDL11. 'soap12/'
  };
 

use constant MSEXT          => SOAP11ENV;


use constant
  { XOP10           => 'http://www.w3.org/2004/08/xop/include'
  , XMIME10         => 'http://www.w3.org/2004/11/xmlmime'
  , XMIME11         => 'http://www.w3.org/2005/05/xmlmime'
  };

1;
