use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use HTTP::Request::Common;
use JSON::MaybeXS;
use Path::Tiny;
use Open311::Endpoint::Integration::UK;

# Need to override the endpoint config, bit fiddly
package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_upload';
    $args{config_data} = '
service_whitelist:
  Flooding & Drainage:
    ABC_DEF: Flooding
';
    return $class->$orig(%args);
};

package main;

# Override config of the Integration package
my $uploads_dir = Path::Tiny->tempdir;

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(config => sub {
    {
        web_url => 'http://www.example.org/web',
        uploads_dir => $uploads_dir,
        tenant_id => 'dummy',
        server_timezone => 'Europe/London',
    }
});
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Graffiti', EnquirySubject => [ { SubjectCode => "DEF" } ] },
            ] } }
        };
    }
    $op = $op->value;
    if ($op->name eq 'NewEnquiry') {
        return { OperationResponse => { NewEnquiryResponse => { Enquiry => { EnquiryNumber => 2001 } } } };
    }
    return {};
});
my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock(get => sub {
    return HTTP::Response->new(200, 'OK', [], '123');
});
$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    return HTTP::Response->new(200, 'OK', [], '{"access_token":"123"}') if $req->uri =~ /oauth\/token/;
    # A file upload
    my $data = decode_json($req->content);
    is $data->{enquiryNumber}, 2001;
    is scalar @{$data->{centralDocLinks}}, 3;
    return HTTP::Response->new(200, 'OK', [], '{}') if $req->uri =~ /centralEnquiries/;
});

# Now the actual tests

use Open311::Endpoint::Integration::UK::Dummy;

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "POST OK with uploads" => sub {
    my $a_file = path(__FILE__);
    my $req = POST '/requests.json',
        Content_Type => 'form-data',
        Content => [
            api_key => 'test',
            service_code => 'ABC_DEF',
            address_string => '22 Acacia Avenue',
            first_name => 'Bob',
            last_name => 'Mould',
            description => "This is the details",
            'attribute[easting]' => 100,
            'attribute[northing]' => 100,
            'attribute[fixmystreet_id]' => 1001,
            'attribute[title]' => 'Title',
            'attribute[description]' => 'This is the details',
            'attribute[report_url]' => 'http://example.com/report/1001',
            'media_url' => 'http://example.com/image/1',
            'media_url' => 'http://example.com/image/2',
            anything => [ $a_file ],
        ];
    my $res = $endpoint->run_test_request($req);
    ok $res->is_success, 'valid request' or diag $res->content;

    is_deeply decode_json($res->content), [ { "service_request_id" => 2001 } ], 'correct json returned';
    my $data = decode_json($uploads_dir->child('2001.json')->slurp_utf8);
    is_deeply $data->{media_url}, [ 'http://example.com/image/1', 'http://example.com/image/2' ];
    is path($data->{uploads}->[0])->basename, $a_file->basename, 'Correct file name stored';
    is $uploads_dir->child('2001', $a_file->basename)->exists, 1, 'Uploaded file copied to right place';
};

subtest 'And test the uploading' => sub {
    my $uk = Open311::Endpoint::Integration::UK->new;
    $uk->confirm_upload;
    # Tests are in the LWP UA mock above
};

done_testing;
