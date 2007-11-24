# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::SOAP::Util;
use vars '$VERSION';
$VERSION = '0.63';
use base 'Exporter';

my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP/;
my @soap12 = qw/SOAP12ENV SOAP12ENC SOAP12RPC
  SOAP12NONE SOAP12NEXT SOAP12ULTIMATE/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;

our @EXPORT_OK = (@soap11, @soap12, @wsdl11);
our %EXPORT_TAGS =
  ( soap11 => \@soap11
  , soap12 => \@soap12
  , wsdl11 => \@wsdl11
  );


use constant SOAP11         => 'http://schemas.xmlsoap.org/soap/';
use constant SOAP11ENV      => SOAP11. 'envelope/';
use constant SOAP11ENC      => SOAP11. 'encoding/';
use constant SOAP11NEXT     => SOAP11. 'actor/next';
use constant SOAP11HTTP     => SOAP11. 'http';


use constant SOAP12         => 'http://www.w3c.org/2003/05/';
use constant SOAP12ENV      => SOAP12. 'soap-envelope';
use constant SOAP12ENC      => SOAP12. 'soap-encoding';
use constant SOAP12RPC      => SOAP12. 'soap-rpc';

use constant SOAP12NONE     => SOAP12ENV.'/role/none';
use constant SOAP12NEXT     => SOAP12ENV.'/role/next';
use constant SOAP12ULTIMATE => SOAP12ENV.'/role/ultimateReceiver';


use constant WSDL11         => 'http://schemas.xmlsoap.org/wsdl/';
use constant WSDL11SOAP     => WSDL11. 'soap/';
use constant WSDL11HTTP     => WSDL11. 'http/';
use constant WSDL11MIME     => WSDL11. 'mime/';
use constant WSDL11SOAP12   => WSDL11. 'soap12/';
 
1;
