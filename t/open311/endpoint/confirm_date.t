use strict;
use warnings;

package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_date';
    $args{config_data} = '{"service_whitelist":{"Roads":{"HM_PHS":"Small pothole"}}}';
    return $class->$orig(%args);
};

package main;

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(config => sub {
    return { server_timezone => "Europe/London" };
});
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'HM', ServiceName => 'Highways', EnquirySubject => [ {
                    SubjectCode => "PHS",
                    SubjectAttribute => [ { EnqAttribTypeCode => 'SINC' } ],
                } ] },
            ],
            EnquiryAttributeType => [
                { EnqAttribTypeCode => 'SINC', MandatoryFlag => 'false', EnqAttribTypeName => 'Abandoned since', EnqAttribTypeFlag => 'D' },
            ],
            } }
        };
    }
    $op = $op->value;
    if ($op->name eq 'NewEnquiry') {
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        my ($code, $value) = ${$req{EnquiryAttribute}}->value;
        is $code->name, 'EnqAttribTypeCode';
        is $value->name, 'EnqAttribDateValue';
        is $code->value, 'SINC';
        is $value->value, '2021-11-11';
        return { OperationResponse => { NewEnquiryResponse => { Enquiry => { EnquiryNumber => 2001 } } } };
    }
    return {};
});

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "POST OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'HM_PHS',
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
        'attribute[SINC]' => '2021-11-11',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

done_testing;
