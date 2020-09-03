#!/usr/bin/env perl

BEGIN {
    use File::Basename qw(dirname);
    use File::Spec;
    my $d = dirname(File::Spec->rel2abs($0));
    require "$d/../setenv.pl";
}

use feature qw/say/;
use Data::Printer;
use Open311::Endpoint::Integration::UK::NorthamptonshireAlloyV2;

my $e = Open311::Endpoint::Integration::UK::NorthamptonshireAlloyV2->new();

my $alloy_id = shift;

die "Please provide the itemId of an Alloy inspection or defect\n" unless $alloy_id;

my @updates = get_updates($alloy_id);
my $defect = get_inspection_defect($alloy_id);
if ($defect) {
    push @updates, get_updates($defect);
}

my @sorted_updates = sort { $a->{date} cmp $b->{date} } @updates;

say "date" . ' ' x 23 . 'itemId (type)' . ' ' x 18 . 'alloy status' . ' ' x 14 . 'fms status, extra';
say "$_->{date} - $_->{id} ($_->{type}) $_->{status}: $_->{mapped}, $_->{extra}" for @sorted_updates;

sub get_inspection_defect {
    my $id = shift;

    my $search = {
        properties =>  {
          dodiCode => "designInterfaces_defects",
          attributes => [
            "attributes_itemsTitle",
            "attributes_itemsSubtitle",
            "attributes_defectStatus"
          ]
        },
        children => [
          {
            type => "Equals",
            children => [
              {
                type => "ItemProperty",
                properties => {
                  itemPropertyName => "itemId",
                  path => "root^attributes_inspectionsRaisingDefectsRaisedDefects"
                }
              },
              {
                type => "AlloyId",
                properties => {
                  value => [
                    $id
                  ]
                }
              }
            ]
          }
        ]
    };

    my $results = $e->alloy->search($search);

    return $results->[0]->{itemId} if $results->[0];
}

sub get_updates {
    my $id = shift;
    my @updates;

    my @versions = $e->get_versions_of_resource($id);

    my $mapping = $e->config->{inspection_attribute_mapping};
    foreach my $date (@versions) {
        my $resource = $e->alloy->api_call(call => "item-log/item/$id/reconstruct", body => { date => $date });
        my $attribs = $e->alloy->attributes_to_hash( $resource->{item} );

        my ($type, $status, $mapped_status, $extra);
        if ( $resource->{item}->{designCode} =~ /inspection/i ) {
            $type = 'INS';
            $status = $attribs->{attributes_tasksStatus}->[0];
            ($mapped_status, $extra) = $e->_get_inspection_status( $attribs, $mapping );
        } else {
            $type = 'DEF';
            $status = $attribs->{attributes_defectsStatus}->[0];
            $mapped_status = $e->defect_status( $status );
        }

        push @updates, {id => $id, type => $type, date => $date, status => $status, mapped => $mapped_status, extra => $extra};
    }

    return @updates;
}

