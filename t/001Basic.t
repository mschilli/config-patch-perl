######################################################################
# Test suite for Config::Patch
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;

use Test::More tests => 14;
use Config::Patch;

my $TDIR = ".";
$TDIR = "t" if -d "t";
my $TESTFILE = "$TDIR/testfile";

END { unlink $TESTFILE; }

BEGIN { use_ok('Config::Patch') };

my $TESTDATA = "abc\ndef\nghi\n";

####################################################
# Single patch 
####################################################
blurt($TESTDATA, $TESTFILE);

my $patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->append(<<'EOT');
This is
a patch.
EOT

    # Check if patch got applied correctly
my($patches, $hashref) = $patcher->patches();
ok(exists $hashref->{"foobarkey"}, "Patch exists");
is($patches->[0]->[0], "foobarkey", "Patch in patch list");
is($patches->[0]->[1], "append", "Patch mode correct");
is($patches->[0]->[2], "This is\na patch.\n", "Patch text correct");

    # Remove patch
$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->remove();

my $data = slurp($TESTFILE);
is($data, $TESTDATA, "Test file intact after removing patch");

####################################################
# Double patch
####################################################
blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->append(<<'EOT');
This is
a patch.
EOT

open FILE, ">>$TESTFILE" or die;
print FILE $TESTDATA;
close FILE;

$patcher->append(<<'EOT');
This is
another patch.
EOT

    # Check if patch got applied correctly
($patches, $hashref) = $patcher->patches();
ok(exists $hashref->{"foobarkey"}, "Patch exists");

is($patches->[0]->[0], "foobarkey", "Patch in patch list");
is($patches->[1]->[0], "foobarkey", "Patch in patch list");

is($patches->[0]->[1], "append", "Patch mode correct");
is($patches->[1]->[1], "append", "Patch mode correct");

is($patches->[0]->[2], "This is\na patch.\n", "1st patch text correct");
is($patches->[1]->[2], "This is\nanother patch.\n", "2nd patch text correct");

    # Remove patch
$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->remove();

$data = slurp($TESTFILE);
is($data, $TESTDATA . $TESTDATA, 
    "Test file intact after removing both patches");

###############################################
sub blurt {
###############################################
    my($data, $file) = @_;
    open FILE, ">$file" or die "Cannot open $file ($!)";
    print FILE $data;
    close FILE;
}

###############################################
sub slurp {
###############################################
    my($file) = @_;

    local $/ = undef;
    open FILE, "<$file" or die "Cannot open $file ($!)";
    my $data = <FILE>;
    close FILE;

    return $data;
}
