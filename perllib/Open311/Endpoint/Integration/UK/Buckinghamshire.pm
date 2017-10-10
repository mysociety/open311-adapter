package Open311::Endpoint::Integration::UK::Buckinghamshire;
use parent 'Open311::Endpoint::Integration::Confirm';

use Moo;

use Integrations::Confirm::Buckinghamshire;


has jurisdiction_id => (
    is => 'ro',
    default => 'buckinghamshire_confirm',
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::Buckinghamshire'
);

has '+service_whitelist' => (
    default => sub { {
        'Flooding & Drainage' => {
            RM_FLO => 'Flooding',
        },
        'Flytipping' => {
            REM_FLYE => 'Rubbish or fly tipping on the roads',
        },
        'Parks & Green Spaces' => {
            RM_GRAS => 'Grass cutting',
            RM_HEDG => 'Hedge problem',
            RM_TREE => 'Trees',
        },
        'Roads & Pavements' => {
            RM_TBOL => 'Bollards or railings',
            RM_FDEF => 'Footpath / pavement problem',
            RM_PHC => 'Pothole',
            RM_RM => 'Road lines / road markings',
            RM_RSD => 'Road surface',
            RM_WEED => 'Weed problem on the highway',
        },
        'Salt & Gritting' => {
            WM_SB => 'Salt bin damaged',
            WM_SBR => 'Salt bin refill',
            WM_GRIT => 'Snow and ice problem/winter salting',
            # => 'Winter salting',
        },
        'Street Lights' => {
            SLRM_SLDB => 'Light on during the day',
            SLRM_SLD => 'Street light dim',
            SLRM_SLI => 'Street light intermittent',
            SLRM_SLO => 'Street light not working',
        },
        'Street Signs' => {
            RM_SIGN => 'Sign problem',
            RM_UAS => 'Unauthorised signs',
        },
        'Traffic Lights' => {
            ITS_SMP => 'Traffic light / crossing - button/beep/lamp',
            ITSR_STIM => 'Traffic light / crossing - timing issues',
        },




        # 'Area Schemes' => {
        #     ASM_ASCH => 1,
        #     ASM_CDRN => 1,
        #     ASM_CR => 1,
        #     ASM_PST2 => 1,
        #     ASM_TCI => 1,
        #     ASM_TRO => 1,
        #     ASM_TS => 1,
        #     ASM_VAS => 1,
        # },

        # 'Asset Management' => {
        #     AM_GAZ => 1,
        #     AM_LP => 1,
        #     AM_MA => 1,
        #     AM_RAD => 1,
        #     AM_TDAT => 1,
        # },

        # 'ITS Reactive' => {
        #     ITS_SCO => 1,
        #     ITS_SDA => 1,
        #     ITS_SMP => 1,
        #     ITS_SOFF => 1,
        # },

        # 'ITS Routine' => {
        #     ITSR_CCTV => 1,
        #     ITSR_RBOL => 1,
        #     ITSR_STIM => 1,
        #     ITSR_SVMS => 1,
        # },

        # 'Network Safety' => {
        #     CR_CDR => 1,
        #     CR_RSE => 1,
        #     CR_SC => 1,
        #     CR_SLE => 1,
        # },

        # 'Parking' => {
        #     PARK_CEA => 1,
        #     PARK_COS => 1,
        #     PARK_DPA => 1,
        #     PARK_ENF => 1,
        #     PARK_NSL => 1,
        #     PARK_PARK => 1,
        #     PARK_PCON => 1,
        #     PARK_WRQ => 1,
        # },

        # 'Reactive Maintenance' => {
        #     REM_CWPT => 1,
        #     REM_EFT => 1,
        #     REM_FLEM => 1,
        #     REM_FLYE => 1,
        #     REM_FUEL => 1,
        #     REM_FWPT => 1,
        #     REM_MDC => 1,
        #     REM_RCL => 1,
        #     REM_RTC => 1,
        # },

        # 'Road Space Management' => {
        #     RSM_AB => 1,
        #     RSM_ACC => 1,
        #     RSM_CAFE => 1,
        #     RSM_CULT => 1,
        #     RSM_DKR => 1,
        #     RSM_DVS => 1,
        #     RSM_EOTS => 1,
        #     RSM_EVE => 1,
        #     RSM_FILM => 1,
        #     RSM_HORD => 1,
        #     RSM_ILL => 1,
        #     RSM_LTRO => 1,
        #     RSM_MAT => 1,
        #     RSM_NRSW => 1,
        #     RSM_PERA => 1,
        #     RSM_ROAD => 1,
        #     RSM_ROP => 1,
        #     RSM_RSB => 1,
        #     RSM_S184 => 1,
        #     RSM_S50 => 1,
        #     RSM_SAG => 1,
        #     RSM_SCAF => 1,
        #     RSM_SDEC => 1,
        #     RSM_SKIP => 1,
        #     RSM_STR => 1,
        #     RSM_SW50 => 1,
        #     RSM_SWI => 1,
        #     RSM_TRC => 1,
        #     RSM_TSI => 1,
        #     RSM_TTRO => 1,
        #     RSM_TTS => 1,
        #     RSM_UCRF => 1,
        #     RSM_UFRF => 1,
        #     RSM_UTIL => 1,
        #     RSM_VAA => 1,
        #     RSM_VAC => 1,
        #     RSM_VAI => 1,
        #     RSM_VX => 1,
        #     RSM_WL => 1,
        # },

        # 'Routine Maintenance' => {
        #     RM_ADP => 1,
        #     RM_APM => 1,
        #     RM_CPM => 1,
        #     RM_CRS => 1,
        #     RM_DEBR => 1,
        #     RM_DRN => 1,
        #     RM_DS => 1,
        #     RM_DTCH => 1,
        #     RM_FDEF => 1,
        #     RM_FLO => 1,
        #     RM_GLLY => 1,
        #     RM_GR => 1,
        #     RM_GRAF => 1,
        #     RM_GRAS => 1,
        #     RM_HEDG => 1,
        #     RM_HM => 1,
        #     RM_KERB => 1,
        #     RM_LTCI => 1,
        #     RM_MAN => 1,
        #     RM_MUD => 1,
        #     RM_OBS => 1,
        #     RM_PATC => 1,
        #     RM_PHC => 1,
        #     RM_PS => 1,
        #     RM_RM => 1,
        #     RM_RS => 1,
        #     RM_RSD => 1,
        #     RM_RWL => 1,
        #     RM_SFP => 1,
        #     RM_SIGN => 1,
        #     RM_SLB => 1,
        #     RM_SPDL => 1,
        #     RM_SUBS => 1,
        #     RM_TBOL => 1,
        #     RM_TPES => 1,
        #     RM_TREE => 1,
        #     RM_UAS => 1,
        #     RM_VERG => 1,
        #     RM_VP => 1,
        #     RM_WEED => 1,
        # },

        # 'Schemes Countywide' => {
        #     SCY_CMCC => 1,
        #     SCY_CMFS => 1,
        # },

        # 'SL Reactive Maintenance' => {
        #     SLRE_BBO => 1,
        #     SLRE_BD => 1,
        #     SLRE_BSM => 1,
        #     SLRE_CDO => 1,
        #     SLRE_CKD => 1,
        #     SLRE_CL => 1,
        #     SLRE_LBH => 1,
        #     SLRE_LH => 1,
        #     SLRE_LUH => 1,
        #     SLRE_MLO => 1,
        #     SLRE_SFM => 1,
        #     SLRE_SPDO => 1,
        #     SLRE_SPKD => 1,
        #     SLRE_SPL => 1,
        #     SLRE_SUV => 1,
        # },

        # 'SL Routine Maintenance' => {
        #     SLRM_BLDB => 1,
        #     SLRM_BLI => 1,
        #     SLRM_BLO => 1,
        #     SLRM_BSD => 1,
        #     SLRM_LD => 1,
        #     SLRM_LDB => 1,
        #     SLRM_LI => 1,
        #     SLRM_LO => 1,
        #     SLRM_SHLD => 1,
        #     SLRM_SLBR => 1,
        #     SLRM_SLD => 1,
        #     SLRM_SLDB => 1,
        #     SLRM_SLDM => 1,
        #     SLRM_SLEQ => 1,
        #     SLRM_SLI => 1,
        #     SLRM_SLO => 1,
        #     SLRM_SLOE => 1,
        #     SLRM_SLR => 1,
        #     SLRM_SLUN => 1,
        #     SLRM_SPD => 1,
        # },

        # 'Structures' => {
        #     STR_BRID => 1,
        #     STR_BRIG => 1,
        #     STR_BRII => 1,
        # },

        # 'Winter Maintenance' => {
        #     WM_GRIT => 1,
        #     WM_SB => 1,
        #     WM_SBR => 1,
        # },
    } }
);

has '+ignored_attributes' => (
    default => sub { [ qw/
        CDR
        CIA
        FTE
    / ] }
);

has '+forward_status_mapping' => (
    default => sub { {
        CLOSED => '700', # "Enquiry completed"
        FIXED => '700', # "Enquiry completed"
        DUPLICATE => '080', # "Duplicate - Job already raised"
        OPEN => undef, # we don't want to reopen an enquiry in Confirm via an FMS update
    } }
);

has '+reverse_status_mapping' => (
    default => sub { {
        # Confirm status code => Open311 status, Confirm name, outstanding
        '050' => 'open', # Enquiry Raised; yes
        '060' => 'open', # Acknowledged; yes
        '070' => 'closed', # Resolved by Contact Centre; no
        '080' => 'duplicate', # Duplicate - Job already raised; yes
        '100' => 'investigating', # Assessment; yes
        '110' => 'open', # Re-assign; yes
        '150' => 'open', # (GC) QS Response; yes
        '160' => 'open', # Further case work required; yes
        '200' => 'open', # (GC)Further case work required; yes
        '205' => 'closed', # No issues identified; no
        '215' => 'closed', # Incomplete Insufficent Info; no
        '220' => 'closed', # Defect below intervention lev.; no
        '230' => 'closed', # Defect not TfB resp.; no
        '250' => 'open', # (GC) Awaiting response; yes
        '270' => 'closed', # (GC) No Evidence; no
        '305' => 'action_scheduled', # Works Programmed; yes
        '310' => 'action_scheduled', # P1 or P2 job raised; yes
        '320' => 'action_scheduled', # P3 job raised; yes
        '330' => 'open', # DNO Supply Fault; yes
        '340' => 'closed', # ROW Maint. & Enforcement Issue; no
        '350' => 'closed', # Non Defect Resolved; no
        '380' => 'closed', # Free Text Email for Resolution; no
        '390' => 'in_progress', # Job Raised; yes
        '400' => 'in_progress', # Works issued; yes
        '450' => 'in_progress', # Works Started; yes
        '470' => 'in_progress', # Works Suspended; yes
        '480' => 'open', # Works Cancelled/Abandoned; yes
        '500' => 'fixed', # Made Safe; no
        '550' => 'closed', # (SW) Application approved; no
        '600' => 'fixed', # Works completed; no
        '601' => 'closed', # (RC) Waiting for Claimant; yes
        '700' => 'fixed', # Enquiry completed; no
        '730' => 'open', # Contact Centre Escalation; yes
        '740' => 'open', # Customer challenge; yes
        '750' => 'internal_referral', # Escalated Customer Response; no
    } }
);

1;
