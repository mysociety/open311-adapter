package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling('gloucester_alloy.yml')->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Gloucester';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling('gloucester_alloy.yml')->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');

has '+testing' => ( default => 1 );

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;
use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my (@sent);

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock('get', sub {
    my ($self, $url) = @_;
    return HTTP::Response->new(200, 'OK', [], '{}');
});

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ( $self, %args ) = @_;

    my $call    = $args{call};
    my $params  = $args{params};
    my $body    = $args{body};
    my $is_file = $args{is_file};

    my $content;

    if ($body) {
        push @sent, $body;

        if ( $call =~ 'item' ) {
            # Creating new report
            $content = path(__FILE__)->sibling(
                'json/alloyv2/gloucester/create_report_response.json')->slurp;

        } elsif ( $call =~ 'aqs/statistics' ) {
            # Counting how many defects there are
            $content = path(__FILE__)->sibling('json/alloyv2/gloucester/defects_count_response.json')->slurp;

        } elsif ( $call =~ 'aqs/query' ) {
            # Querying defects
            $content = path(__FILE__)->sibling("json/alloyv2/gloucester/defects_query_response.json")->slurp;

        }

    } else {
        if ( $call =~ 'item/680125dbf87b692e8cf5def9' ) {
            # Looking up created report - returning the same response as for
            # newly created report
            $content = path(__FILE__)->sibling(
                'json/alloyv2/gloucester/create_report_response.json')->slurp;

        } elsif ( $call =~ 'item/5c8bdfb98ae862230019dc20' ) {
            # Looking up status object for "Confirmed" status
            $content = path(__FILE__)->sibling("json/alloyv2/gloucester/status_confirmed.json")->slurp;

        } elsif ( $call =~ 'item/63806a7105cb25039365ec1d' ) {
            # Looking up status object for "Cancelled" status
            $content = path(__FILE__)->sibling("json/alloyv2/gloucester/status_cancelled.json")->slurp;

        } elsif ( $call =~ 'item/.*/parents' ) {
            # Looking up defect parents - returning no parents
            $content = path(__FILE__)->sibling("json/alloyv2/gloucester/empty_response.json")->slurp;

        } elsif ( $call =~ 'item-log/item/([^/]*)' ) {
            # Looking up individual defect
            my $id = $1;
            $content
                = path(__FILE__)
                ->sibling("json/alloyv2/gloucester/item_log_${id}.json")->slurp;

        } else {
            die "No handler found for API call $call";
        }

    }

    if ( !$content ) {
        warn 'No handler found for API call ' . $call;
        return decode_json('[]');
    }

    return decode_json( encode_utf8($content) );
});

subtest 'check metadata set for given services' => sub {
    subtest "Faded nameplate (can't read easily)" => sub {
        my $res = $endpoint->run_test_request(
            GET => '/services/Faded_nameplate_1.json' );
        ok $res->is_success, 'json success';

        my $content = decode_json( $res->content );
        is @{ $content->{attributes} }, 9, 'has metadata attributes';
    };

    subtest 'Dead animal that needs removing' => sub {
        my $res = $endpoint->run_test_request(
            GET => '/services/Dead_animal_that_needs_removing.json' );
        ok $res->is_success, 'json success';

        my $content        = decode_json( $res->content );
        my ($type_of_animal) = grep { $_->{code} eq 'type_of_animal' }
            @{ $content->{attributes} };

        is_deeply $type_of_animal, {
            code                 => 'type_of_animal',
            datatype             => 'singlevaluelist',
            datatype_description => '',
            description          => 'Type of animal?',
            order                => 10,
            required             => 'true',
            variable             => 'true',
            values               => [
                map { key => $_, name => $_ },
                'Cat',
                'Dog',
                'Other domestic (e.g. horse)',
                'Livestock (e.g. cows)',
                'Small wild animal (e.g. birds, mice)',
                'Large wild animal (e.g. swan, badger)',
                'Other',
            ],
        };

    };

    subtest 'Dog fouling' => sub {
        my $res = $endpoint->run_test_request(
            GET => '/services/Dog_fouling.json' );
        ok $res->is_success, 'json success';

        my $content         = decode_json( $res->content );
        my ($did_you_witness) = grep { $_->{code} eq 'did_you_witness' }
            @{ $content->{attributes} };

        is_deeply $did_you_witness, {
            code                 => 'did_you_witness',
            datatype             => 'singlevaluelist',
            datatype_description => '',
            description          => 'Did you witness the dog fouling?',
            order                => 10,
            required             => 'true',
            variable             => 'true',
            values => [ map { key => $_, name => $_ }, qw/Yes No/ ],
        };

    };
};

subtest 'send new report to Alloy' => sub {
    set_fixed_time('2025-04-01T12:00:00Z');

    my %shared_params = (
        jurisdiction_id => 'dummy',
        api_key => 'test',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => 'title',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[fixmystreet_id]' => 123,
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
    );

    subtest 'No category group' => sub {
        my $res = $endpoint->run_test_request(
            POST => '/requests.json',

            %shared_params,

            service_code => 'Dead_animal_that_needs_removing',
            'attribute[category]' => 'Dead animal that needs removing',
            'attribute[type_of_animal]' => 'Other',
        );

        my $sent = pop @sent;
        $sent->{attributes}
            = [ sort { $a->{attributeCode} cmp $b->{attributeCode} }
                @{ $sent->{attributes} } ];
        is_deeply $sent, {
            attributes => [
                {   attributeCode =>
                        'attributes_customerContactAnimalType_67617293b20d22b010bf32e6',
                    value => ['5d8a50dfca31500a9469aba2'],
                },
                {   attributeCode =>
                        'attributes_customerContactCRMReference_630e97373c0f4b0153a32650',
                    value => '123',
                },
                {   attributeCode =>
                        'attributes_customerContactCategory_630e927746f558015aa26062',
                    value => ['67612c6e97567c437eb2b190'],
                },
                {   attributeCode =>
                        'attributes_customerContactCustomerComments_630e97d11aff300150181403',
                    value => "title\n\ndescription\n\nType of animal?\nOther",
                },
                { attributeCode =>
                        'attributes_customerContactPriorities_630e8d78afc533014f6cce97',
                    value => ['61827451d1b798015bba7e4c']
                },
                {   attributeCode =>
                        'attributes_customerContactServiceArea_630e905e1aff30015017e892',
                    value => ['630e8f0b3c0f4b0153a2ff36'],
                },
                {   attributeCode =>
                        'attributes_customerContactSubCategory_630e951646f558015aa26b41',
                    value => ['61daed49fdc7a101544177de'],
                },
                {   attributeCode =>
                        'attributes_customerContactTargetDate_63105e3a46f558015ab4c576',
                    value => '2025-04-02T22:59:59Z',
                },
                {   attributeCode =>
                        'attributes_defectsReportedDate',
                    value => '2025-04-01T12:00:00Z',
                },
                {   attributeCode =>
                        'attributes_itemsGeometry',
                    value => {
                        coordinates => [ 0.1, 50 ],
                        type => 'Point',
                    },
                },
            ],
            designCode => 'designs_customerContact_630e8c4b46f558015aa248b0',
            parents    => {},
        }, 'correct json sent';

        ok $res->is_success, 'valid request'
            or diag $res->content;

        is_deeply decode_json( $res->content ),
            [ { service_request_id => '680125dbf87b692e8cf5def9' } ],
            'correct json returned';
    };

    subtest 'With category group and service area' => sub {
        my $res = $endpoint->run_test_request(
            POST => '/requests.json',

            %shared_params,

            service_code => 'Dog_fouling',
            'attribute[category]' => 'Dog fouling',
            'attribute[group]' => 'Broken glass or other hazard',
            'attribute[did_you_witness]' => 'Yes',
        );

        my $sent = pop @sent;
        $sent->{attributes}
            = [ sort { $a->{attributeCode} cmp $b->{attributeCode} }
                @{ $sent->{attributes} } ];
        is_deeply $sent, {
            attributes => [
                {   attributeCode =>
                        'attributes_customerContactCRMReference_630e97373c0f4b0153a32650',
                    value => '123',
                },
                {   attributeCode =>
                        'attributes_customerContactCategory_630e927746f558015aa26062',
                    value => ['61c0b9fefb9e76015838c1d4'],
                },
                {   attributeCode =>
                        'attributes_customerContactCustomerComments_630e97d11aff300150181403',
                    value => "title\n\ndescription\n\nDid you witness the dog fouling?\nYes",
                },
                { attributeCode =>
                        'attributes_customerContactPriorities_630e8d78afc533014f6cce97',
                    value => ['67d12b067e3fda851c204b2f']
                },
                {   attributeCode =>
                        'attributes_customerContactServiceArea_630e905e1aff30015017e892',
                    value => ['630e8f0b3c0f4b0153a2ff36'],
                },
                {   attributeCode =>
                        'attributes_customerContactSubCategory_630e951646f558015aa26b41',
                    value => ['61ba198c7148450165fff23f'],
                },
                {   attributeCode =>
                        'attributes_customerContactTargetDate_63105e3a46f558015ab4c576',
                    value => '2025-06-24T22:59:59Z',
                },
                {   attributeCode =>
                        'attributes_defectsReportedDate',
                    value => '2025-04-01T12:00:00Z',
                },
                {   attributeCode =>
                        'attributes_itemsGeometry',
                    value => {
                        coordinates => [ 0.1, 50 ],
                        type => 'Point',
                    },
                },
            ],
            designCode => 'designs_customerContact_630e8c4b46f558015aa248b0',
            parents    => {},
        }, 'correct json sent';

        ok $res->is_success, 'valid request'
            or diag $res->content;

        is_deeply decode_json( $res->content ),
            [ { service_request_id => '680125dbf87b692e8cf5def9' } ],
            'correct json returned';
    };

    subtest 'Same group, different service areas' => sub {
        my $res = $endpoint->run_test_request(
            POST => '/requests.json',

            %shared_params,

            service_code => 'Damaged_dog_bin',
            'attribute[category]' => 'Damaged dog bin',
            'attribute[group]' => 'Litter bins',
        );

        my $sent = pop @sent;
        $sent->{attributes}
            = [ sort { $a->{attributeCode} cmp $b->{attributeCode} }
                @{ $sent->{attributes} } ];
        is_deeply $sent, {
            attributes => [
                {   attributeCode =>
                        'attributes_customerContactCRMReference_630e97373c0f4b0153a32650',
                    value => '123',
                },
                {   attributeCode =>
                        'attributes_customerContactCategory_630e927746f558015aa26062',
                    value => ['61b9e12d67018e015a67ec25'],
                },
                {   attributeCode =>
                        'attributes_customerContactCustomerComments_630e97d11aff300150181403',
                    value => "title\n\ndescription",
                },
                { attributeCode =>
                        'attributes_customerContactPriorities_630e8d78afc533014f6cce97',
                    value => ['67d12b067e3fda851c204b2f']
                },
                {   attributeCode =>
                        'attributes_customerContactServiceArea_630e905e1aff30015017e892',
                    value => ['630e8f183c0f4b0153a2ff5c'],
                },
                {   attributeCode =>
                        'attributes_customerContactSubCategory_630e951646f558015aa26b41',
                    value => ['61b9e1ccfb9e760158036bc1'],
                },
                {   attributeCode =>
                        'attributes_customerContactTargetDate_63105e3a46f558015ab4c576',
                    value => '2025-04-29T22:59:59Z',
                },
                {   attributeCode =>
                        'attributes_defectsReportedDate',
                    value => '2025-04-01T12:00:00Z',
                },
                {   attributeCode =>
                        'attributes_itemsGeometry',
                    value => {
                        coordinates => [ 0.1, 50 ],
                        type => 'Point',
                    },
                },
            ],
            designCode => 'designs_customerContact_630e8c4b46f558015aa248b0',
            parents    => {},
        }, 'correct json sent';

        ok $res->is_success, 'valid request'
            or diag $res->content;

        #####

        $res = $endpoint->run_test_request(
            POST => '/requests.json',

            %shared_params,

            service_code => 'Overflowing_litter_bin',
            'attribute[category]' => 'Overflowing litter bin',
            'attribute[group]' => 'Litter bins',
        );

        $sent = pop @sent;
        $sent->{attributes}
            = [ sort { $a->{attributeCode} cmp $b->{attributeCode} }
                @{ $sent->{attributes} } ];
        is_deeply $sent, {
            attributes => [
                {   attributeCode =>
                        'attributes_customerContactCRMReference_630e97373c0f4b0153a32650',
                    value => '123',
                },
                {   attributeCode =>
                        'attributes_customerContactCategory_630e927746f558015aa26062',
                    value => ['61b9e12d67018e015a67ec25'],
                },
                {   attributeCode =>
                        'attributes_customerContactCustomerComments_630e97d11aff300150181403',
                    value => "title\n\ndescription",
                },
                { attributeCode =>
                        'attributes_customerContactPriorities_630e8d78afc533014f6cce97',
                    value => ['61827451d1b798015bba7e4c']
                },
                {   attributeCode =>
                        'attributes_customerContactServiceArea_630e905e1aff30015017e892',
                    value => ['630e8f0b3c0f4b0153a2ff36'],
                },
                {   attributeCode =>
                        'attributes_customerContactSubCategory_630e951646f558015aa26b41',
                    value => ['61b9e1127148450165fd145f'],
                },
                {   attributeCode =>
                        'attributes_customerContactTargetDate_63105e3a46f558015ab4c576',
                    value => '2025-04-29T22:59:59Z',
                },
                {   attributeCode =>
                        'attributes_defectsReportedDate',
                    value => '2025-04-01T12:00:00Z',
                },
                {   attributeCode =>
                        'attributes_itemsGeometry',
                    value => {
                        coordinates => [ 0.1, 50 ],
                        type => 'Point',
                    },
                },
            ],
            designCode => 'designs_customerContact_630e8c4b46f558015aa248b0',
            parents    => {},
        }, 'correct json sent';

        ok $res->is_success, 'valid request'
            or diag $res->content;

    };
};

subtest 'fetch updates from Alloy' => sub {
    my $res
        = $endpoint->run_test_request( GET =>
            '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2023-11-13T11:00:00Z&end_date=2023-11-13T11:59:59Z',
        );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json( $res->content ), [
        {   description => '',
            media_url => '',
            external_status_code => 'Confirmed',
            extras => {
                latest_data_only => 1
            },
            updated_datetime => '2023-11-13T11:05:00Z',
            service_request_id => 'defect_1',
            update_id => 'defect_1_20231113110500',
            status => 'in_progress'
        },
        {   description => '',
            media_url => '',
            external_status_code => 'Cancelled',
            extras => {
                latest_data_only => 1
            },
            updated_datetime => '2023-11-13T11:05:00Z',
            service_request_id => 'defect_2',
            update_id => 'defect_2_20231113110500',
            status => 'closed'
        },
    ], 'correct json returned';
};

subtest 'send updates to Alloy' => sub {
        my $res = $endpoint->run_test_request(
            POST => '/servicerequestupdates.json',
            jurisdiction_id => 'dummy',
            api_key => 'test',

            service_request_id => '680125dbf87b692e8cf5def9',
            service_code => 'Broken_glass',
            status => 'OPEN',
            update_id => '1',
            updated_datetime => '2023-05-15T14:55:55+00:00',

            description => 'Hey, this is still a problem',
        );
        ok $res->is_success, 'valid request'
            or diag $res->content;

        my $sent = pop @sent;
        my $attributes = $sent->{attributes};
        is_deeply $attributes, [
            {   'attributeCode' =>
                    'attributes_customerContactAdditionalComments_67d91d7ea058928de1c00876',
                'value' => 'Customer update at 2023-05-15 14:55:55
Hey, this is still a problem',
            },
        ];

        is_deeply decode_json( $res->content ), [ {
            update_id => '680125dd0004c8ff5436404c',
        } ], 'correct json returned';

};

done_testing;
