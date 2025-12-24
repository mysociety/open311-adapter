package Open311::Endpoint::Integration::UK::Dumfries;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
with 'Role::Memcached';

use Encode;
use JSON::MaybeXS;
use Path::Tiny;

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    return $class->$orig(%args);
};

=head2 process_attributes

In addition to the default new request processing, this function:
* Finds or creates a contact and adds them under the C<contact.attribute_id> attribute.
* Sets the 'reported issue' (i.e. category) field by the incoming service_code.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $contact_resource_id = $self->_find_or_create_contact($args);
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{service_code},
        value => [ $args->{service_code} ],
    };

    return $attributes;
}

=head2 _get_service_code

Dumfries uses the actual Alloy item IDs from their subcategory list on Alloy
as Open311 service codes. This means we can hae different names shown for
groups/subcategories on FMS as well as the same subcategory name used
multiple times for different Alloy IDs (e.g. the 'Other' subcategory in their
'Trees' group has a different item ID to 'Other' in 'Grounds').

=cut

sub _get_service_code {
    my ($self, $group, $subcategory, $subcategory_config) = @_;

    return $subcategory_config->{id};
}

=head2 _get_inspection_status

The Open311 status of a defect in Alloy depends on multiple fields - status,
priority, and outcome.

Because it'd be better to not hardcode these dependencies, the
`inspection_status_mapping` config for Dumfries is a list of objects that we
iterate through to find one that matches the values of those fields on this
defect.

If any of status/outcome/priority are set to null in the
inspection_status_mapping list then those attributes are ignored when
considering if that entry matches.

If we fall off the end of the list with no matches we return 'IGNORE' so the
defect/update is skipped.

=cut

# Mapping is passed in here, but then ignored and looked up again - tidy up the ALloy 'external status code' code? TODO
sub _get_inspection_status {
    my ($self, $defect, $mapping) = @_;
    return $self->inspection_status($defect);
}

sub inspection_status {
    my ($self, $defect) = @_;

    my $mapping = $self->config->{inspection_attribute_mapping};
    my $options = $self->config->{inspection_status_mapping};

    my $status = $defect->{$mapping->{status}} || '';
    my $outcome = $defect->{$mapping->{outcome}} || '';
    my $hwy_priority = $defect->{$mapping->{hwy_priority}} || '';
    my $se_priority = $defect->{$mapping->{se_priority}} || '';

    # unwrap values if necessary
    $status = $status->[0] if ref $status eq 'ARRAY';
    $outcome = $outcome->[0] if ref $outcome eq 'ARRAY';
    $hwy_priority = $hwy_priority->[0] if ref $hwy_priority eq 'ARRAY';
    $se_priority = $se_priority->[0] if ref $se_priority eq 'ARRAY';

    # Enquiry only has one priority, take whichever has a value.
    my $priority = $hwy_priority || $se_priority;

    for my $opt (@$options) {
        unless (defined $opt->{result}) {
            die "Missing 'result' value - please check inspection_status_mapping in config";
        }
        # if the entry in config has some values undefined then consider those fields a match
        my $s = defined $opt->{status}   ? $opt->{status}   eq $status   : 1;
        my $o = defined $opt->{outcome}  ? $opt->{outcome}  eq $outcome  : 1;
        my $p = defined $opt->{priority} ? $opt->{priority} eq $priority : 1;

        # choose this status iff all three things match
        if ($s && $o && $p) {
            return $opt->{result};
        }
    }

    return "IGNORE";
}

sub _skip_inspection_update {
    my ($self, $status) = @_;

    return 1 if $status eq 'IGNORE';
}



1;
