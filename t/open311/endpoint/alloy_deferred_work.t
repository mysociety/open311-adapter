package DumfriesTest;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Dumfries';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling('dumfries_alloy.yml')->stringify;
    return $class->$orig(%args);
};

package main;

use strict;
use warnings;

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);
use Open311::Endpoint::Integration::UK;

BEGIN { $ENV{TEST_MODE} = 1; }

my $uploads_dir = Path::Tiny->tempdir;

my $base_config = LoadFile(path(__FILE__)->sibling('dumfries_alloy.yml')->stringify);

my @api_calls;

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock('get', sub {
    my ($self, $url) = @_;
    return HTTP::Response->new(200, 'OK', [], '{}');
});

# Mock config on the base Integrations::AlloyV2 class so all instances pick up
# uploads_dir — including the real UK::Dumfries plugin instantiated by UK->new.
my $integ_mock = Test::MockModule->new('Integrations::AlloyV2');
$integ_mock->mock('config', sub {
    return { %$base_config, uploads_dir => "$uploads_dir" };
});

$integ_mock->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call    = $args{call};
    my $body    = $args{body};
    my $method  = $args{method} || '';
    my $is_file = $args{is_file};

    push @api_calls, \%args;

    if ($is_file) {
        return { fileItemId => 'file_001' };
    }

    if ($method eq 'PUT' && $call =~ m{^item/(.+)$}) {
        my $item_id = $1;
        return { item => { itemId => $item_id } };
    }

    if ($body) {
        if ($call =~ m{^item$} && $body->{designCode} eq 'designs_contacts') {
            return decode_json('{ "item": { "itemId": "contact_123" } }');
        } elsif ($call =~ m{^item$}) {
            return decode_json('{ "item": { "itemId": "defect_001" } }');
        } elsif ($call eq 'aqs/statistics') {
            return { results => [{ value => { value => 0 } }] };
        }
    }
});

my $endpoint = DumfriesTest->new;

subtest 'POST writes deferred work to JSON file' => sub {
    @api_calls = ();

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dumfries_alloy',
        api_key => 'test',
        service_code => '678f678f' x 3,
        address_string => '1 High Street',
        first_name => 'Test',
        last_name => 'User',
        email => 'test@example.com',
        phone => '07700900123',
        description => 'Street light issue',
        lat => '55.0611',
        long => '-3.6056',
        'attribute[description]' => 'Street light issue',
        'attribute[title]' => 'Street light on High Street',
        'attribute[report_url]' => 'http://localhost/789',
        'attribute[group]' => 'Street Lighting',
        'attribute[category]' => 'Other',
        'attribute[fixmystreet_id]' => 124,
        'attribute[easting]' => 300000,
        'attribute[northing]' => 600000,
        media_url => 'http://example.org/photo/1.jpeg',
    );

    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [{ service_request_id => 'defect_001' }];

    my @inspection_put_calls = grep {
        ($_->{method} || '') eq 'PUT' && $_->{call} =~ /inspection/
    } @api_calls;
    is scalar(@inspection_put_calls), 0, 'no inline PUT to inspection made';

    my $json_file = $uploads_dir->child('defect_001.json');
    ok $json_file->is_file, 'deferred work JSON written';

    my $data = decode_json($json_file->slurp_utf8);
    is $data->{item_id}, 'defect_001', 'item_id correct';
    is $data->{service_code_alloy}, '678f678f' x 3, 'service_code_alloy correct';
    is_deeply $data->{files}, ['file_001'], 'uploaded file IDs stored';
    ok $data->{created_at}, 'created_at timestamp present';
};

subtest 'process_deferred_work completes deferred work' => sub {
    # Re-mock api_call so defect_001 now has an inspection linked
    $integ_mock->mock('api_call', sub {
        my ($self, %args) = @_;

        my $call = $args{call};
        push @api_calls, \%args;

        if ($call eq 'item/defect_001') {
            return { item => {
                itemId => 'defect_001',
                attributes => [{
                    attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                    value => ['inspection_001'],
                }],
            }};
        } elsif ($call eq 'item/inspection_001') {
            return { item => {
                itemId => 'inspection_001',
                designCode => 'designs_hWYCustomerReport',
                attributes => [],
            }};
        }
    });

    @api_calls = ();
    $endpoint->process_deferred_work;

    my $json_file = $uploads_dir->child('defect_001.json');
    ok !$json_file->is_file, 'deferred work JSON removed after success';

    my @put_calls = grep { ($_->{method} || '') eq 'PUT' } @api_calls;
    is scalar(@put_calls), 2, 'two PUT calls made (files + status)';

    my ($file_put) = grep {
        my $attrs = $_->{body}{attributes};
        $attrs && grep { $_->{attributeCode} eq 'attributes_filesAttachableAttachments' } @$attrs;
    } @put_calls;
    ok $file_put, 'PUT call for file attachment found';

    my ($status_put) = grep {
        my $attrs = $_->{body}{attributes};
        $attrs && grep { $_->{attributeCode} eq 'attributes_tasksStatus' } @$attrs;
    } @put_calls;
    ok $status_put, 'PUT call for status update found';
};

done_testing;
