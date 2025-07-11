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

    my @messages;
    foreach (
        { key => 'assisted_yn', label => 'Assisted collection?' },
        { key => 'location_of_containers', label => 'Location of containers:' },
        { key => 'location_of_letterbox', label => 'Location of letterbox:' },
        { key => 'pension', label => 'State pension?' },
        { key => 'disability', label => 'Physical disability?' },
    ) {
        push @messages, "$_->{label} $args->{attributes}->{$_->{key}}"
            if $args->{attributes}->{$_->{key}};
    }

    return join("\n\n", @messages);
}

__PACKAGE__->run_if_script;
