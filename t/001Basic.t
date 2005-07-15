######################################################################
# Test suite for Config::Patch
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;

use Test::More qw(no_plan);
BEGIN { use_ok('Config::Patch') };

ok(1);
like("123", qr/^\d+$/);
