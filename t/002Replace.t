######################################################################
# Test suite for Config::Patch (replace functions)
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;

use Test::More tests => 12;
use Config::Patch;

use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

my $TDIR = ".";
$TDIR = "t" if -d "t";
my $TESTFILE = "$TDIR/testfile";

END { unlink $TESTFILE; }

BEGIN { use_ok('Config::Patch') };

my $TESTDATA = "abc\ndef\nghi\n";

####################################################
# Search/Replace
####################################################
Config::Patch::blurt($TESTDATA, $TESTFILE);

my $patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr(def), "weird stuff\nin here!");
my $data = Config::Patch::slurp($TESTFILE);
$data =~ s/^#.*\n//mg;
is($data, "abc\nweird stuff\nin here!\nghi\n", "content replaced");

$patcher->remove();
$data = Config::Patch::slurp($TESTFILE);
is($data, "abc\ndef\nghi\n", "content restored");

####################################################
# Comment out
####################################################
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->comment_out(qr(def));
$data = Config::Patch::slurp($TESTFILE);
$data =~ s/^#.*\n//mg;
is($data, "abc\nghi\n", "content commented out");

$patcher->remove();
$data = Config::Patch::slurp($TESTFILE);
is($data, "abc\ndef\nghi\n", "content restored");

####################################################
# Double match within a line
####################################################
$TESTDATA = "abc\nabc_def_ghi_def\nghi\n";
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr(def), "weird stuff\nin here!");
$data = Config::Patch::slurp($TESTFILE);
my $finds = 0;
while($data =~ /weird/g) {
    $finds++;
}
is($finds, 1, "Only one replacement with mult matches per line");

$patcher->remove();
$data = Config::Patch::slurp($TESTFILE);
is($data, $TESTDATA, "content restored");

####################################################
# Dont accept the same patch key twice
####################################################
$TESTDATA = "abc\ndef\nghi\n";
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr(def), "weird stuff\nin here!");
my $rc = $patcher->replace(qr(abc), "weird stuff\nin here!");
ok(! defined $rc, "Not allowing the same patch key twice");

####################################################
# Prevent matching in patch code
####################################################
$TESTDATA = "abc\ndef\nghi\n";
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr(def), "weird stuff\nin here!");

$patcher->key("2ndkey");
$patcher->replace(qr(Config), "Doom!");

$data = Config::Patch::slurp($TESTFILE);
unlike($data, qr/Doom/, "Don't match on text in patch code");

$patcher->key("foobarkey");
$patcher->remove();
$data = Config::Patch::slurp($TESTFILE);
is($data, $TESTDATA, "content restored");

####################################################
# Replace two different matches
####################################################
$TESTDATA = "abc\ndef\nghi\n";
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr([cg]), "weird stuff\nin here!");

$data = Config::Patch::slurp($TESTFILE);
like($data, qr/weird.*?weird/s, "Two matches/patches");

$patcher->remove();
$data = Config::Patch::slurp($TESTFILE);
is($data, $TESTDATA, "content restored");

####################################################
# Check patch regions
####################################################
$TESTDATA = "abc\ndef\nghi\n";
Config::Patch::blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");
$patcher->replace(qr([cg]), "weird stuff\nin here!");
my($aref, $href) = $patcher->patches();
#use Data::Dumper;
#print Dumper($aref);
