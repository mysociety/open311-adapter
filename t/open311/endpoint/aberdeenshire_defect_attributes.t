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

    like $description, qr/We've recorded a defect at this location/, 'Contains boilerplate text';
    like $description, qr/To be completed by: 2025-08-15/, 'Contains formatted target date';
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

    like $description, qr/We've recorded a defect at this location/, 'Contains boilerplate text';
    unlike $description, qr/To be completed by/, 'Does not contain target date when missing';
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

    like $description, qr/We've recorded a defect at this location/, 'Contains boilerplate text';
    like $description, qr/To be completed by: 2025-08-15/, 'Contains target date even with API error';
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

    like $description, qr/We've recorded a defect at this location/, 'Contains boilerplate text';
    like $description, qr/To be completed by: 2025-08-15/, 'Contains target date';
    # Should not attempt to fetch attributes without mapping config
    unlike $description, qr/Priority|Surface|Depth/, 'Does not contain attributes without mapping config';
};

subtest "Test defect description with feature attributes (CCAT and SPD)" => sub {
    # Mock json_web_api_call to return defect attributes
    $confirm_mock->mock(json_web_api_call => sub {
        my ($self, $path) = @_;

        if ($path eq '/defects/54321') {
            return {
                defectNumber => '54321',
                attributes => []
            };
        }

        return {};
    });

    my $defect = {
        defectNumber => '54321',
        targetDate => '2025-09-20T12:00:00Z',
        feature => {
            attribute_CCAT => {
                attributeValueCode => '2'
            },
            attribute_SPD => {
                attributeValueCode => '30'
            }
        }
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Road Defect',
        service_code => 'ROAD',
        description => 'Road surface defect'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/We've recorded a defect at this location/, 'Contains boilerplate text';
    like $description, qr/To be completed by: 2025-09-20/, 'Contains formatted target date';
    like $description, qr/Carriageway Category: Category 2/, 'Contains CCAT feature attribute with mapped value';
    like $description, qr/Speed Limit: 30 mph/, 'Contains SPD feature attribute with mapped value';
};

subtest "Test defect description with feature attributes without value mapping" => sub {
    my $defect = {
        defectNumber => '54322',
        targetDate => '2025-09-21T14:30:00Z',
        feature => {
            attribute_CCAT => {
                attributeValueCode => '4'
            },
            attribute_SPD => {
                attributeValueCode => '50'
            }
        }
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Road Defect',
        service_code => 'ROAD',
        description => 'Road surface defect'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/Carriageway Category: 4/, 'Contains unmapped CCAT value as-is';
    like $description, qr/Speed Limit: 50/, 'Contains unmapped SPD value as-is';
};

subtest "Test defect description with both defect and feature attributes" => sub {
    # Mock json_web_api_call to return defect attributes
    $confirm_mock->mock(json_web_api_call => sub {
        my ($self, $path) = @_;

        if ($path eq '/defects/67890') {
            return {
                defectNumber => '67890',
                attributes => [
                    {
                        name => 'Priority Level',
                        type => { key => 'priority' },
                        pickValue => { key => 'high' },
                        currentValue => 'High Priority'
                    }
                ]
            };
        }

        return {};
    });

    my $defect = {
        defectNumber => '67890',
        targetDate => '2025-10-01T09:00:00Z',
        feature => {
            attribute_CCAT => {
                attributeValueCode => '1'
            },
            attribute_SPD => {
                attributeValueCode => '20'
            }
        }
    };

    my $service = Open311::Endpoint::Service->new(
        service_name => 'Pothole',
        service_code => 'POTHOLE',
        description => 'Road pothole'
    );

    my $description = $endpoint->_description_for_defect($defect, $service);

    like $description, qr/Priority: High Priority/, 'Contains defect attribute';
    like $description, qr/Carriageway Category: Category 1/, 'Contains CCAT feature attribute';
    like $description, qr/Speed Limit: 20 mph/, 'Contains SPD feature attribute';
};

done_testing;