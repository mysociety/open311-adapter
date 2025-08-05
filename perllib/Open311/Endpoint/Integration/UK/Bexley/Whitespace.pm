package Open311::Endpoint::Integration::UK::Bexley::Whitespace;

use Moo;
extends 'Open311::Endpoint::Integration::Whitespace';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_whitespace';
    return $class->$orig(%args);
};

sub _worksheet_message {
    my ($self, $args) = @_;

    my @attributes = $args->{service_code} eq 'bulky_collection' ? (
        { key => 'fixmystreet_id', label => 'Booking reference:' },
        { key => 'collection_date', label => 'Collection date:' },
        { key => 'bulky_location', label => 'Location of items:' },
        { key => 'bulky_parking', label => 'Parking restrictions:' },
    ) : (
        { key => 'assisted_yn', label => 'Assisted collection?' },
        { key => 'location_of_containers', label => 'Location of containers:' },
        { key => 'location_of_letterbox', label => 'Location of letterbox:' },
    );

    my @messages;
    foreach (@attributes) {
        my $val = $args->{attributes}->{ $_->{key} };

        next unless $val;

        if ( $_->{key} eq 'collection_date' ) {
            my $orig_val = $val;

            my $dtf_from = DateTime::Format::Strptime->new(
                pattern => '%Y-%m-%d',
            );
            my $dtf_to = DateTime::Format::Strptime->new(
                pattern => '%d/%m/%Y',
            );

            # Undef if error
            $val = $dtf_from->parse_datetime($val);
            $val = $dtf_to->format_datetime($val) if $val;

            # Just send original string if it's faulty
            $val = $orig_val unless $val;
        }

        push @messages, "$_->{label} $val";
    }

    return join("\n\n", @messages);
}

__PACKAGE__->run_if_script;
