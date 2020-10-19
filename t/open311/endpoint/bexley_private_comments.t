package Open311::Endpoint::Integration::UK::Dummy;

use Moo;
extends 'Open311::Endpoint::Integration::UK::Bexley';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Dummy'],
    instantiate => 'new';

has integration_without_prefix => (
    is => 'ro',
    default => 'ConfirmTrees',
);

package Open311::Endpoint::Integration::UK::Dummy::ConfirmTrees;

use Moo;
extends 'Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_data} = '
service_whitelist:
  Trees:
    TREE_BRANCH: Fallen branches
';
    return $class->$orig(%args);
};

package main;

use strict;
use warnings;

use Test::More;
use Test::MockModule;

use Open311::Endpoint::Integration::UK::Dummy;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $confirm_integration = Test::MockModule->new('Integrations::Confirm');
$confirm_integration->mock(config => sub {
    {
        web_url => 'http://www.example.org/web',
        tenant_id => 'dummy',
        server_timezone => 'Europe/London',
    }
});
$confirm_integration->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'TREE', ServiceName => 'Fallen branches', EnquirySubject => [ { SubjectCode => "BRANCH" } ] },
            ] } }
        };
    }
    $op = $op->value;
    if ($op->name eq 'NewEnquiry') {
        # Check that private comments are included in the description.
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        is $req{EnquiryDescription}, "This is the details\nPrivate comments: Testing private comments";
        return { OperationResponse => { NewEnquiryResponse => { Enquiry => { EnquiryNumber => 2001 } } } };
    }
});

subtest "Sending private comments to Confirm when creating new report" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'TREE_BRANCH',
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
        'attribute[private_comments]' => "Testing private comments",
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    # Test for private comments appearing in description is in the `perform_request`
    # mock above this test.
};

done_testing;
