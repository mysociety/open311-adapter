package Open311::Endpoint::Integration::UK::Hackney;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_highways_alloy_v2';
    return $class->$orig(%args);
};

has '+group_in_service_code' => (
    is => 'ro',
    default => 0
);

sub service_request_content {
    '/open311/service_request_extended'
}

# basic services creating without setting up attributes from Alloy
sub services {
    my $self = shift;

    my @services = ();
    my %categories = ();
    for my $group (sort keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $subcategory (sort keys %{ $whitelist }) {
            $categories{$subcategory} ||= [];
            push @{ $categories{$subcategory} }, $group;
        }
    }

    for my $category (sort keys %categories) {
        my $name = $category;
        my $code = $name;
        my %service = (
            service_name => $name,
            description => $name,
            service_code => $code,
            groups => $categories{$category},
        );
        my $o311_service = $self->service_class->new(%service);

        push @services, $o311_service;
    }

    return @services;
}

sub process_attributes {
    my ($self, $source, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($source, $args);

    # The way the reporter's contact information gets included with a
    # inspection is Northamptonshire-specific, so it's handled here.
    # Their Alloy set up attaches a "Contact" resource to the
    # inspection resource via the "caller" attribute.

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # Unlike Northants, Hackney has an item for each category (not group).
    # Not every category on the FMS side has a matching attribute value in Alloy,
    # so the default_category_attribute_value config value is used when the
    # service code doesn't exist in category_list_code, because a value is
    # required by Alloy.
    my $group_code = $self->_find_category_code($args->{service_code}) || $self->config->{default_category_attribute_value};
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

sub _find_or_create_contact {
    my ($self, $args) = @_;

    if (my $contact = $self->_find_contact($args->{email})) {
        return $contact->{itemId};
    } else {
        return $self->_create_contact($args)->{item}->{itemId};
    }
}

sub _find_contact {
    my ($self, $email, $phone) = @_;

    my ($attribute_code, $search_term);
    if ( $email ) {
        $search_term = $email;
        $attribute_code = $self->config->{contact}->{search_attribute_code_email};
    } elsif ( $phone ) {
        $search_term = $phone;
        $attribute_code = $self->config->{contact}->{search_attribute_code_phone};
    } else {
        return undef;
    }

    my $body = {
        properties => {
            dodiCode => $self->config->{contact}->{code},
            collectionCode => "Live"
        },
        children => [
            {
                type => "GlobalAttributeSearch",
                children=> [
                    {
                        type => "String",
                        properties => {
                            value => [$search_term]
                        }
                    }
                ]
            }
        ]
    };

    my $results = $self->alloy->search($body);

    return undef unless @$results;
    return $results->[0];
}

sub _create_contact {
    my ($self, $args) = @_;

    # For true/false values we have to use the JSON()->true/false otherwise
    # when we convert to JSON later we get 1/0 which then fails the validation
    # at the Alloy end
    # NB: have to use 'true'/'false' strings in the YAML for this to work. If we
    # use true/false then it gets passed in as something that gets converted to 1/0
    #
    # we could possibly use local $YAML::XS::Boolean = "JSON::PP" in the Config module
    # to get round all this but not sure if that would break something else.
    my $defaults = {
        map {
            $_ => $self->config->{contact}->{attribute_defaults}->{$_} =~ /^(true|false)$/
                ? JSON()->$1
                : $self->config->{contact}->{attribute_defaults}->{$_}
        } keys %{ $self->config->{contact}->{attribute_defaults} }
    };

    # phone cannot be null;
    $args->{phone} ||= '';

    # XXX should use the created time of the report?
    my $now = DateTime->now();
    my $created_time = DateTime::Format::W3CDTF->new->format_datetime($now);
    $args->{created} = $created_time;

    # include the defaults which map to themselves in the mapping
    my $remapping = {
        %{$self->config->{contact}->{attribute_mapping}},
        map {
            $_ => $_
        } keys %{ $self->config->{contact}->{attribute_defaults} }
    };

    $args = {
        %$args,
        %$defaults
    };

    my @attributes = @{ $self->alloy->update_attributes( $args, $remapping, []) };

    my $contact = {
        designCode => $self->config->{contact}->{code},
        attributes => \@attributes,
        geometry => undef,
    };

    return $self->alloy->api_call(
        call => "item",
        body => $contact
    );
}

1;
