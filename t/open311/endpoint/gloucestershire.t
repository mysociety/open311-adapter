package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config { { server_timezone => 'Europe/London' } }

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1 };

use Open311::Endpoint::Integration::UK::Gloucestershire;
use Test::More;
use Test::MockModule;

my $class = Open311::Endpoint::Integration::UK::Gloucestershire->new(
    config_data => <<HERE,
integration_class: Integrations::Confirm::Dummy
default_site_code: 123456
forward_status_mapping:
  OPEN: 123
  OPEN_REPORTER: 456
  CLOSED: 789
HERE
);

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    $op = $op->value;
    if ($op->name eq 'EnquiryUpdate') {
        # Check contents of req here
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        if ($req{EnquiryNumber} eq '1001') {
            is $req{EnquiryStatusCode}, 123;
        } elsif ($req{EnquiryNumber} eq '1002') {
            is $req{EnquiryStatusCode}, 456;
        }
        return { OperationResponse => { EnquiryUpdateResponse => { Enquiry => { EnquiryNumber => 2001, EnquiryLogNumber => 2 } } } };
    }
    return {};
});

subtest process_service_request_args => sub {
    my $args = {
        attributes => {
            description =>
                'Less deep than a golf ball, smaller than a dinner plate | Report title',
            fixmystreet_id => '2157',
            location       => 'Report detail',
            report_url => 'http://gloucestershire.localhost:3000/report/2157',
            title => 'Should ultimately populate description',
        },
        description  => 'Should be overridden by attributes description',
        service_code => 'pothole_road',
    };

    is_deeply $class->process_service_request_args($args), {
        attributes => { fixmystreet_id => '2157' },

        description =>
            'Less deep than a golf ball, smaller than a dinner plate | Report title',
        location     => 'Report detail',
        report_url   => 'http://gloucestershire.localhost:3000/report/2157',
        service_code => 'pothole_road',
        site_code    => '123456',
    };
};

subtest 'update by reporter' => sub {
    my @req = (
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        update_id => 123,
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
    );
    my $res = $class->run_test_request(
        @req,
        service_request_id => 1001,
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    $res = $class->run_test_request(
        @req,
        service_request_id => 1002,
        'attribute[by_reporter]' => 1,
    );
    ok $res->is_success, 'valid request' or diag $res->content;
};

done_testing();
