=head1 NAME

Open311::Endpoint::Integration::UK::BANES - Bath and North East Somerset integration set-up

=head1 SYNOPSIS

BANES manage their own Open311 server to receive all reports made on FMS, whether in
email categories or in those created by their Confirm integration. The Confirm
integration only receives the reports in categories in its services.

=cut

package Open311::Endpoint::Integration::UK::BANES;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::BANES'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'banes',
);

=head2 _map_with_new_id & _map_from_new_id

BANES's two endpoints do not overlap in service_codes as the Passthrough
accepts all reports with email addresses and the others are Confirm.
This code overrides the default Multi code to not change anything,
and cope accordingly.

=cut

sub _map_with_new_id {
    my ($self, $attributes, @results) = @_;

    @results = map {
        my ($name, $result) = @$_;
        $result;
    } @results;

    return @results;
}

my $email_regex = qr/\@.*?\./;

sub _map_from_new_id {
    my ($self, $code, $type) = @_;

    my $integration;
    if ($type eq 'service') {
        if ($code =~ /$email_regex/) {
            $integration = 'Passthrough';
        } else {
            $integration = 'Confirm';
        }
    }

    return ($integration, $code);
}

__PACKAGE__->run_if_script;
