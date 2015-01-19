#!/usr/bin/python

import xmlrpclib
import sys
server = xmlrpclib.ServerProxy('https://bugzilla-test.gnome.org/xmlrpc.cgi')
try:
    result = server.GNOME.addversionx({'product': 'foobar', 'version': '1.2.3.4'})
except xmlrpclib.Fault, e:
    print "FAILED (%s)" % e.faultString
    sys.exit(1)
except Exception, e:
    print "FAILED (%s)" % e.strerror
    sys.exit(1)
else:
    print result
    sys.exit(0)
