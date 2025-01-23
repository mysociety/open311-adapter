=head1 NAME

Open311::Endpoint::Integration::UK::Bristol::Alloy - Bristol-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Bristol::Alloy;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
use JSON::MaybeXS;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bristol_alloy';
    return $class->$orig(%args);
};

sub rfs_design_fallback { 'SC-Street Cleansing' }

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $attributes_values = $self->config->{'request_attribute_to_values'};
    my $code = $args->{service_code_alloy};
    if (grep { $code =~ /$_/ } keys %{$self->config->{service_whitelist}->{'SC-Street Cleansing'}}) {
        my $value;
        if ($code eq 'Dead animal') {
            $value = [ $attributes_values->{TypeOfAnimal}->[ $args->{attributes}->{TypeOfAnimal} ] ];
        } else {
            $value = [ $attributes_values->{CleansingTypes}->{$code} ];
        }
        $args->{service_code_alloy} = 'SC-Street Cleansing';

        my $myattrib = {
            attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{$args->{service_code_alloy}}->{'JobType'},
            value => $value,
        };

        push @$attributes, $myattrib;
    };

    my $attributes_names = $self->config->{request_to_resource_attribute_manual_mapping}->{$args->{service_code_alloy}};

    for my $att (keys %$attributes_names) {
        next if $att eq 'JobType';
        next unless length $args->{attributes}->{$att};

        my $myattrib = {
            attributeCode => $attributes_names->{$att},
            value => $attributes_values->{$att} ?  $attributes_values->{$att}->[ $args->{attributes}->{$att} ] : $args->{attributes}->{$att},
        };

        if ($myattrib->{value} =~ /^[01]$/) {
            $myattrib->{value} = $myattrib->{value} ? JSON->true : JSON->false;
        } elsif ($attributes_values->{$att}) {
            $myattrib->{value} = [ $myattrib->{value} ];
        }

        push @$attributes, $myattrib;
    };

    my $usrn = $args->{attributes}->{'usrn'};

    if (length($usrn) == 7) {
        $usrn = "0" . $usrn;
    };
    my $locality_name = $self->_search_for_code_by_argument(
        {
            'dodi_code' => $self->config->{street_cleaning_network_details}->{code},
            'attribute' => $self->config->{street_cleaning_network_details}->{attribute},
            "search" => $usrn,
        }
    );

    my $locality = $self->_search_for_code_by_argument(
        {
            'dodi_code' => $self->config->{locality_list_details}->{code},
            'attribute' => $self->config->{locality_list_details}->{attribute},
            "search" => $locality_name->{attributes}->{ $self->config->{locality_attribute_field} },
        }
    );

    my $text = $args->{attributes}->{title} . "\n\n" . $args->{attributes}->{description};
    my @extras = (
        {
            attributeCode => $self->config->{extra_attribute_mapping}->{$args->{service_code_alloy}}->{fullText_attribute},
            value => $text
        },
        {
            attributeCode => $self->config->{extra_attribute_mapping}->{$args->{service_code_alloy}}->{locality_attribute},
            value => [ $locality->{itemId} ]
        },
    );
    for my $extra (@extras) {
        push @$attributes, $extra;
    };

    return $attributes;
}

1;
