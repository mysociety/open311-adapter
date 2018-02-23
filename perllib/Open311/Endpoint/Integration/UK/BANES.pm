package Open311::Endpoint::Integration::UK::BANES;
use parent 'Open311::Endpoint::Integration::Confirm';

use Moo;

use Integrations::Confirm::BANES;

has jurisdiction_id => (
    is => 'ro',
    default => 'banes_confirm',
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::BANES'
);

has '+ignored_attributes' => (
    default => sub { [ qw/
        AAC
        ACK
        AD
        AV10
        AV11
        AV12
        AV13
        AV7
        AV8
        AV9
        AW
        CF
        CFP
        DT
        EAST
        NORT
        OHV
        OWS2
        OWST
        PPFB
        PPFG
        PPFL
        PPFO
        PRN
        RS
        RSS
        ST
        VEA1
        VEA2
        VEGO
    / ] }
);

has '+service_whitelist' => (
    default => sub { {
        "Flooding & Drainage" => {
            NM_BD => 1, # Blocked drain (doesn't seem to exist on Confirm yet)
            NM_RG => 1, # Blocked gully
            NM_FL => 1,  # Flooding
        },
        "Hazard or Obstruction on Highway" => {
            NM_ARH => "Objects in the road", # Articles on the Highway
            NM_DB => "Mud or Debris on the road", # Mud or Debris on the Highway
            NM_OV => 1, # Overhanging Vegetation
            NM_OF => "Spillage on the road", # Spillage on Highway
            NM_VC => "Verge cutting required", # Verge Cutting
        },
        "Roads & Pavements (e.g. Potholes)" => {
            NM_LW => "Faded road markings", # Lining works
            NM_PH => "Pothole/road damage",
            NM_RK => "Damage to pavement", # Pavement Repair
        },
        "Street Fixtures & Shelters" => {
            NM_BOP => "Damaged bollard or post", # Bollard/Post Repair
            PT_BS => "Bus stop/shelter issue", # Bus stops/shelters
            NM_GB => "Grit bin issue", # Grit Bins
            NM_IW => "Damaged Railing, manhole, or drain cover", # Ironwork Repair
            NM_RS => "Damaged road sign", # Road Sign
            NM_SNP => "Damaged street nameplate", # Street Nameplates
        },
    } }
);

has '+service_assigned_officers' => (
    default => sub { { PT_BS => 'AE' } }
);

has '+forward_status_mapping' => (
    default => sub { {
        OPEN => 'NEW',
        NO_FURTHER_ACTION => 'NOFA',
    } }
);


has '+reverse_status_mapping' => (
    default => sub { {
        'ADHC' => 'action_scheduled', # No Action Now - In Program
        'COCP' => 'fixed', # Contractor Completed
        'DUPL' => 'duplicate', # Duplicated Record
        'ENR' => 'investigating', # Enquiry Rejected
        'FTDN' => 'closed', # Fourteen Day Notice
        'INNA' => 'closed', # Insp Complete - No Action Req
        'INAR' => 'action_scheduled', # Insp Complete - Action Req
        'INOS' => 'fixed', # Inspector resolved on site
        'INSP' => 'investigating', # Inspection Required
        'LL' => 'open', # Letter Logged
        'NEW' => 'open', # New Entry - No action Yet
        'NOFA' => 'closed', # No Further Action
        'ORDR' => 'action_scheduled', # Placed on Works Order
        'PAD' => 'internal_referral', # Passed to another department
        'PAU' => 'internal_referral', # Passed to utility to resolve
        'PEPC' => 'closed', # Return Phone Call - Resolved
        'REFE' => 'open', # Referred to Section Head
        'RESC' => 'action_scheduled', # Leave for Cyclic Maintenance
        'RESL' => 'closed', # Resolved - Letter Sent
        'RESM' => 'closed', # Resolved - Email Sent
        'RESP' => 'open', # Return Phone Call - Unresolved
        'TEDN' => 'closed', # Twenty Eight Day Notice

        # These are all to be removed from Confirm. Leaving them here
        # until this happens.
        'CONT' => 'action_scheduled', # Issued to Contractor
        'EL' => 'open', # Email Logged
        'EMSI' => 'open', # Emergency Services Informed
        'EXP' => 'closed', # Licence Expired
        'LLC' => 'open', # Letter Logged - Councillor
        'LLI' => 'open', # Letter Logged Internal
        'RESE' => 'fixed', # Resolved when enquiry made
        'RESI' => 'closed', # Resolved - Licence Issued
        'RESN' => 'closed', # No Action Taken
        'SDN' => 'open', # Seven Day Notice
    } }
);

has '+attribute_descriptions' => (
    default => sub { {
        RF => 'Is the road flooded?',
        PF => 'Is the pavement flooded?',
        PRF => 'Is a property flooded?',
        SOFF => 'Can you identify the source of the flooding?',
        BS => 'Is the paving slab broken?',
        DK => 'Is the kerb damaged?',
        MS => 'Is a paving slab missing?',
        PSU => 'Is the pavement surface poor/damaged?',
        PTBS => 'Type of issue',
        RQ => 'Type of issue',
        IT => 'Type of issue',
        SL => 'Is the sign missing / damaged',
    } }
);

has '+ignored_attribute_options' => (
    default => sub { [ qw/
        NK
    / ] }
);

1;
