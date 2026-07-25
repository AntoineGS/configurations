#!/usr/bin/env perl

use strict;
use warnings;
use MIME::Base64 qw(encode_base64);

binmode STDIN, ':raw';
binmode STDOUT, ':raw';

while (defined(my $path = <STDIN>)) {
    $path =~ s/\n\z//;
    print encode_base64($path, q{}), "\0", $path, "\0";
}
