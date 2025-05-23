package Open311::Endpoint::Service::Attribute;
use Moo;
use MooX::HandlesVia;
use Types::Standard ':all';
use namespace::clean;

# from http://wiki.open311.org/GeoReport_v2#GET_Service_Definition

# A unique identifier for the attribute
has code => (
    is => 'ro',
    isa => Str,
);

# true denotes that user input is needed
# false means the attribute is only used to present information to the user within the description field
#
# NB: unsure what false means for the rest of the options here, e.g. should remainder of fields by Maybe[] ?
has variable => (
    is => 'ro',
    isa => Bool,
    default => sub { 1 },
);

# Denotes the type of field used for user input.
has datatype => (
    is => 'ro',
    isa => Enum[qw/ string number datetime text singlevaluelist multivaluelist /],
);

has required => (
    is => 'ro',
    isa => Bool,
);

# A description of the datatype which helps the user provide their input
has datatype_description => (
    is => 'ro',
    isa => Str,
    default => '',
);

# A description of the attribute field with instructions for the user to find
# and identify the requested information
has description => (
    is => 'ro',
    isa => Str,
);

# indicates an attribute that should not be show to the user
has automated => (
    is => 'ro',
    isa => Enum[qw/ server_set hidden_field /],
);

# NB: we don't model the "Order" field here, as that's really for the Service
# object to return

# only relevant for singlevaluelist or multivaluelist
has values => (
    is => 'ro',
    isa => HashRef,
    default => sub { {} },
    handles_via => 'Hash',
    handles => {
        get_value => 'get',
        get_values => 'keys',
        has_values => 'count',
        values_kv => 'kv',
    }
);

# for singlevaluelist or multivalue list, allow any value so we don't have to
# hardcode a list when defining attribute.
has allow_any_value => (
    is => 'ro',
    isa => Bool,
    default => sub { 0 },
);


has values_sorted => (
    is => 'ro',
    isa => ArrayRef,
    default => sub { [] },
    handles_via => 'Array',
    handles => {
        get_sorted_values => 'elements',
        has_sorted_values => 'count',
    }
);

sub schema_definition {
    my $self = shift;

    my @values = map +{ type => '//str', value => $_ }, $self->get_values;
    # FMS will send a blank string for optional singlevaluelist attributes where
    # the user didn't make a selection. Make sure this is allowed by the schema.
    push(@values, { type => '//str', value => '' }) unless $self->required;
    # Some integrations have extra fields whose options are managed within
    # the FMS admin rather than being fixed. For these we need to ensure
    # we can accept any value.
    push(@values, { type => '//str' }) if $self->allow_any_value;

    my %schema_types = (
        string => '//str',
        number => '//num',
        datetime => '//str', # TODO
        text => '//str',
        singlevaluelist => { type => '//any', of => [@values] },
        # Either a single value or a non-empty list of values.
        multivaluelist => { type => '//any', of => [{ type => '//any', of => [@values]}, { type => '//arr', contents => { type => '//any', of => [@values] }, length => { min => 1 } }] },
    );

    return $schema_types{ $self->datatype };
}

1;
