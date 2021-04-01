package Open311::Endpoint::Integration::UK::Bexley;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Bexley'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'bexley',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'Symology',
);

around post_service_request => sub {
    my ($orig, $class, $integration, $report) = @_;

    # Add private comments
    my $private_comments = delete $report->{attributes}{private_comments};
    $report->{description} .= "\nPrivate comments: " . $private_comments if $private_comments;

    # Confirm overwrites the description with the one from the attributes,
    # so add private comments there as well.
    if ($report->{attributes}->{description}) {
        $report->{attributes}->{description} .= "\nPrivate comments: " . $private_comments if $private_comments;
    }

    return $class->$orig($integration, $report);
};

__PACKAGE__->run_if_script;
