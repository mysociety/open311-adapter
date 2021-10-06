#!/usr/bin/env perl

use strict;
use warnings;
require 5.8.0;
use feature qw(say);

BEGIN {
    use File::Basename qw(dirname);
    use File::Spec;
    my $d = dirname(File::Spec->rel2abs($0));
    require "$d/../setenv.pl";
}
use YAML::XS qw(LoadFile);

=for comment

This should be a YAML file with the following keys:

* client_id - the Salesforce client id
* client_secret - the Salesforce client secret
* redirect_url - the redirect url registered for the app
* live - 1 if it's live, 0 if it's test

=cut

my $conf_file = shift;

die "Please provide a config file name with client details\n" unless $conf_file;

my $conf = LoadFile($conf_file) or die "Failed to load $conf_file: $!\n";

my $client_id = $conf->{client_id};
my $client_secret = $conf->{client_secret};
my $redirect_url = $conf->{redirect_url};

my $salesforce_url = $conf->{live} ? 'https://login.salesforce.com' : 'https://test.salesforce.com';

say <<END
visit this url:

$salesforce_url/services\/oauth2/authorize?response_type=code\&client_id=$client_id\&redirect_uri=$redirect_url\&state=mystate

And then paste in the URL you are redirected to after you have logged in:

END
;

chomp(my $url = <STDIN>);

die "You need to paste in a URL\n" unless $url;

my ($code) = ($url =~ /code=([^&]*)/);

die "There didn't seem to be a code in there :(\n" unless $code;

say <<END

now run this command and grab the auth token from the output:

curl --header "Accept: application/json" --header "Content-Type: application/x-www-form-urlencoded" --data 'grant_type=authorization_code\&client_id=$client_id\&client_secret=$client_secret\&redirect_uri=$redirect_url\&code=$code' $salesforce_url/services/oauth2/token

END
;
