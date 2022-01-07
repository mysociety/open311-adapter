package Open311::Endpoint::Integration::UK::NorthamptonshireAlloyV2;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northamptonshire_alloy_v2';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
}

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    # The way the reporter's contact information gets included with a
    # inspection is Northamptonshire-specific, so it's handled here.
    # Their Alloy set up attaches a "Contact" resource to the
    # inspection resource via the "caller" attribute.

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # For category we use the group and not the category
    my ( $group, $category ) = split('_', $args->{service_code});
    my $group_code = $self->_find_category_code($group);
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $group_code ],
    };

    # Attach the caller to the inspection attributes
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    return $attributes;

}

sub get_request_description {
    my ($self, $desc, $req) = @_;

    my ($group, $category) = $self->get_defect_category($req) =~ /([^_]*)_(.*)/;

    my $attributes = $self->alloy->attributes_to_hash($req);

    my $priority;
    for my $att (keys %$attributes) {
        if ($att =~ /Priorities/ ) {
            $priority = $attributes->{$att}->[0];
        }
    }

    if ($priority) {
        my $priority_details = $self->alloy->api_call(
            call => "item/$priority"
        );

        $attributes = $self->alloy->attributes_to_hash($priority_details->{item});
        my $timescale = $attributes->{attributes_itemsTitle};
        $timescale =~ s/P\d+, P\d+ - (.*)/$1/;


        $desc = "Our Inspector has identified a $group defect at this location and has issued a works ticket to repair under the $category category. We aim to complete this work within the next $timescale.";
    }

    return $desc;
}

sub skip_fetch_defect {
    my ( $self, $defect ) = @_;

    my $a = $self->alloy->attributes_to_hash( $defect );
    return 1 if $self->SUPER::skip_fetch_defect($defect) || $self->_get_defect_fms_id( $a );

    return 0;
}

# We want to ignore and updates that were made during and before the migration
# to alloy V2 as the might lead to sprurious updates on FixMyStreet.
sub _valid_update_date {
    my ($self, $update, $update_time) = @_;

    if ( $self->alloy->config->{update_cutoff_date} ) {
        my $cutoff = $self->date_to_dt( $self->alloy->config->{update_cutoff_date} );
        my $update_dt = $self->date_to_truncated_dt( $update_time );

        return 0 if $update_dt < $cutoff;
    }

    return 1;
}

sub _get_defect_fms_id {
    my ($self, $attributes) = @_;

    my $fms_id;
    if (my @ids = grep { $_ =~ /StreetDoctorID/ && $attributes->{$_} } keys %{ $attributes } ) {
        $fms_id = $attributes->{$ids[0]};
    }

    return $fms_id;
}

sub _generate_update {
    my ($self, $args, $updates) = @_;

    my @contacts = map { $args->{$_} } grep { $args->{$_} } qw/ email phone /;
    my $time = $self->date_to_dt($args->{updated_datetime});
    my $formatted_time = $time->ymd . " " . $time->hms;
    $updates .= sprintf(
        "\nCustomer %s %s [%s] update at %s\n%s",
        $args->{first_name},
        $args->{last_name},
        join(',', @contacts),
        $formatted_time,
        $args->{description}
    );

    return $updates;
}

1;
