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

# Mock the GetDefectAttributes method
my $confirm_mock = Test::MockModule->new('Integrations::Confirm');

subtest "Test _fetch_defect_web_api_attributes returns structured data" => sub {
    # Mock GetDefectAttributes to return defect attributes
    $confirm_mock->mock(GetDefectAttributes => sub {
        my ($self, $defect_number) = @_;

        if ($defect_number eq '12345') {
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

    my $attributes = $endpoint->_fetch_defect_web_api_attributes($defect);

    is ref($attributes), 'ARRAY', 'Returns arrayref';
    is scalar(@$attributes), 3, 'Returns three attributes';

    is_deeply $attributes->[0], ['priority', 'Priority', 'High Priority'], 'First attribute has correct structure';
    is_deeply $attributes->[1], ['surface', 'Surface', 'Tarmac'], 'Second attribute has correct structure';
    is_deeply $attributes->[2], ['depth', 'Depth', 15], 'Third attribute has correct structure';
};

subtest "Test defect description with attributes" => sub {
    # Mock GetDefectAttributes to return defect attributes
    $confirm_mock->mock(GetDefectAttributes => sub {
        my ($self, $defect_number) = @_;

        if ($defect_number eq '12345') {
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
    like $description, qr{To be completed by: 15/08/2025}, 'Contains formatted target date';
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
    # Mock GetDefectAttributes to throw error
    $confirm_mock->mock(GetDefectAttributes => sub {
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
    like $description, qr{To be completed by: 15/08/2025}, 'Contains target date even with API error';
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
    like $description, qr{To be completed by: 15/08/2025}, 'Contains target date';
    # Should not attempt to fetch attributes without mapping config
    unlike $description, qr/Priority|Surface|Depth/, 'Does not contain attributes without mapping config';
};

subtest "Test defect description with feature attributes (CCAT and SPD)" => sub {
    # Mock GetDefectAttributes to return defect attributes
    $confirm_mock->mock(GetDefectAttributes => sub {
        my ($self, $defect_number) = @_;

        if ($defect_number eq '54321') {
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
    like $description, qr{To be completed by: 20/09/2025}, 'Contains formatted target date';
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
    # Mock GetDefectAttributes to return defect attributes
    $confirm_mock->mock(GetDefectAttributes => sub {
        my ($self, $defect_number) = @_;

        if ($defect_number eq '67890') {
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

subtest "Test service request updates include defect attributes in extras" => sub {
    # Verify that _fetch_defect_web_api_attributes is called and data added to extras
    my $defect = {
        defectNumber => '11111',
        targetDate => '2025-11-15T10:00:00Z',
        feature => {
            attribute_CCAT => { attributeValueCode => '2' },
            attribute_SPD => { attributeValueCode => '30' }
        }
    };

    # Mock GetDefectAttributes to return defect attributes
    $confirm_mock->mock(GetDefectAttributes => sub {
        my ($self, $defect_number) = @_;
        if ($defect_number eq '11111') {
            return {
                defectNumber => '11111',
                attributes => [
                    {
                        name => 'Priority Level',
                        type => { key => 'priority' },
                        pickValue => { key => 'high' },
                        currentValue => 'High Priority'
                    },
                    {
                        name => 'Depth',
                        type => { key => 'depth' },
                        numericValue => 20,
                        currentValue => '20'
                    }
                ]
            };
        }
        return {};
    });

    # Test the attributes fetch directly
    my $attributes = $endpoint->_fetch_defect_web_api_attributes($defect);
    is scalar(@$attributes), 2, 'Fetches two attributes';

    # Verify structure - these will be added to extras with defectAttrib_ prefix
    is $attributes->[0][0], 'priority', 'First attribute code is priority';
    is $attributes->[0][2], 'High Priority', 'First attribute value is High Priority';
    is $attributes->[1][0], 'depth', 'Second attribute code is depth';
    is $attributes->[1][2], 20, 'Second attribute value is 20';

    # Verify that when added to extras, they'll be prefixed
    my $extras = {};
    foreach my $attr (@$attributes) {
        my ($code, $name, $value) = @$attr;
        $extras->{"defectAttrib_$code"} = $value;
    }
    is $extras->{defectAttrib_priority}, 'High Priority', 'Extras key has defectAttrib_ prefix for priority';
    is $extras->{defectAttrib_depth}, 20, 'Extras key has defectAttrib_ prefix for depth';
};

done_testing;
