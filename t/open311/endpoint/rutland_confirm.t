package Integrations::Confirm::Rutland::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("rutland_confirm.yml")->stringify }

package Open311::Endpoint::Integration::UK::Rutland::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Rutland::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'rutland_confirm';
    $args{config_file} = path(__FILE__)->sibling("rutland_confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Rutland::Dummy');

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
          return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
              { EnquiryNumber => 2020, EnquiryStatusLog => [ { EnquiryLogNumber => 5, StatusLogNotes => 'Private status log notes', LogEffectiveTime => '2026-01-23T12:00:00Z', LoggedTime => '2026-01-23T12:00:00Z', EnquiryStatusCode => 'AFMS' }, { EnquiryLogNumber => 6, StatusLogNotes => 'Private status log notes', LogEffectiveTime => '2026-01-23T12:00:00Z', LoggedTime => '2026-01-23T12:00:00Z', EnquiryStatusCode => 'FMSA' }, { EnquiryLogNumber => 7, StatusLogNotes => 'Public status log notes', LogEffectiveTime => '2026-01-23T12:00:00Z', LoggedTime => '2026-01-23T12:00:00Z', EnquiryStatusCode => 'FMS' } ] },
          ] } } };
});

my $endpoint = Open311::Endpoint::Integration::UK::Rutland::Confirm::Dummy->new;

subtest "Only uses the photo with the correct classification tag" => sub {
    my @photos = (
        {
            URL => '1',
            Name => '1.jpg',
            Date => DateTime->now->subtract(days => 1),
            ClassificationCode => 'DT10',
        },
        {
            URL => '2',
            Name => '2.jpg',
            Date => DateTime->now->subtract(days => 2),
            ClassificationCode => 'DT20',
        },
        {
            URL => '3',
            Name => '3.jpg',
            Date => DateTime->now->subtract(days => 3),
        },
    );
    my @filtered = $endpoint->filter_photos_graphql(@photos);

    is @filtered, 1;
    is $filtered[0]->{URL}, 2;
};

subtest 'Only pass on log notes for updates for "FMS" status' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2018-01-01T00:00:00Z&end_date=2018-02-01T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<update_id>2020_5</update_id>';
    contains_string $res->content, '<update_id>2020_6</update_id>';
    contains_string $res->content, '<update_id>2020_7</update_id>';
    lacks_string $res->content, 'Private status log notes';
    contains_string $res->content, 'Public status log notes';
    contains_string $res->content, '<status>unchanged</status>';
};

done_testing;

