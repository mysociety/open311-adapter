package Integrations::Confirm::AberdeenshireDummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("aberdeenshire_defect_attributes.yml")->stringify }

package Open311::Endpoint::Integration::UK::AberdeenshireDummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Aberdeenshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'aberdeenshire_defect_attributes_dummy';
    $args{config_file} = path(__FILE__)->sibling("aberdeenshire_defect_attributes.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::AberdeenshireDummy');

package main;

use strict;
use warnings;

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;
use HTTP::Response;

BEGIN { $ENV{TEST_MODE} = 1; }

my $lwp = Test::MockModule->new('LWP::UserAgent');
my $endpoint = Open311::Endpoint::Integration::UK::AberdeenshireDummy->new;

# Mock the json_web_api_call method directly
my $confirm_mock = Test::MockModule->new('Integrations::Confirm');

subtest "Test defect description with attributes" => sub {
    # Mock json_web_api_call to return defect attributes
    $confirm_mock->mock(json_web_api_call => sub {
        my ($self, $path) = @_;

        if ($path eq '/defects/12345') {
            return {
                defectNumber => '12345',
                attributes => [
                    {
                        name => 'Priority Level',
                        type => { key => 'priority' },
                        pickValue => { key => 'high' },
                        currentValue => 'High Priority'
                    },
                    {
                        name => 'Surface Type',
                        type => { key => 'surface' },
                        pickValue => { key => 'tarmac' },
                        currentValue => 'Tarmac'
                    },
                    {
                        name => 'Depth',
                        type => { key => 'depth' },
                        numericValue => 15,
                        currentValue => '15'
                    }
                ]
            };
        }

        return {};
    });

    my $defect = {
        defectNumber => '12345',
        targetDate => '2025-08-15T10:00:00Z'
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Pothole Repair',
        service_code => 'POTHOLE',
        description => 'Road surface pothole repair'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/Defect type: Pothole Repair/, 'Contains service name';
    like $description, qr/Target completion date: 2025-08-15/, 'Contains formatted target date';
    like $description, qr/Priority: High Priority/, 'Contains priority attribute';
    like $description, qr/Surface: Tarmac/, 'Contains surface attribute with mapped value';
    like $description, qr/Depth: 15/, 'Contains numeric depth attribute';
};

subtest "Test defect description without target date" => sub {
    my $defect = {
        defectNumber => '12345'
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Street Light',
        service_code => 'LIGHT',
        description => 'Street light repair'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/Defect type: Street Light/, 'Contains service name';
    unlike $description, qr/Target completion date/, 'Does not contain target date when missing';
};

subtest "Test defect description with API error" => sub {
    # Mock json_web_api_call to throw error
    $confirm_mock->mock(json_web_api_call => sub {
        die "API Error";
    });

    my $defect = {
        defectNumber => '99999',
        targetDate => '2025-08-15T10:00:00Z'
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Sign Repair',
        service_code => 'SIGN',
        description => 'Traffic sign repair'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/Defect type: Sign Repair/, 'Contains service name even with API error';
    like $description, qr/Target completion date: 2025-08-15/, 'Contains target date even with API error';
    # Should not contain attribute info when API fails
    unlike $description, qr/Priority|Surface|Depth/, 'Does not contain attributes when API fails';
};

subtest "Test defect description without attribute mapping config" => sub {
    # Create endpoint without defect_attributes config
    my $simple_endpoint = Open311::Endpoint::Integration::UK::AberdeenshireDummy->new;

    # Override config to not have defect_attributes
    my $integration = $simple_endpoint->get_integration;
    $integration->{config} = { endpoint_url => 'test' };

    my $defect = {
        defectNumber => '12345',
        targetDate => '2025-08-15T10:00:00Z'
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Barrier Repair',
        service_code => 'BARRIER',
        description => 'Safety barrier repair'
    );

    my $description = $simple_endpoint->_description_for_defect($defect, $service);

    like $description, qr/Defect type: Barrier Repair/, 'Contains service name';
    like $description, qr/Target completion date: 2025-08-15/, 'Contains target date';
    # Should not attempt to fetch attributes without mapping config
    unlike $description, qr/Priority|Surface|Depth/, 'Does not contain attributes without mapping config';
};

done_testing;