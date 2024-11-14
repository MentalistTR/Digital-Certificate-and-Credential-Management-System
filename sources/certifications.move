module credentials::certifications {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::linked_table::{Self, LinkedTable};
    use std::string::String;

    // Error codes
    const ENotAuthorized: u64 = 0;
    const EInstitutionNotFound: u64 = 1;
    const ECertificateNotFound: u64 = 2;
    const EInvalidCredential: u64 = 3;
    const EAlreadyVerified: u64 = 4;
    const EExpiredCredential: u64 = 5;
    const EInsufficientPoints: u64 = 6;
    const EBadgeNotEarned: u64 = 7;
    const EChallengeNotActive: u64 = 8;
    const EPrerequisitesNotMet: u64 = 9;
    const EInvalidEndorsement: u64 = 10;

    // Core structs
    public struct Platform has key {
        id: UID,
        admin: address,
        revenue: Balance<SUI>,
        verification_fee: u64
    }

    public struct Institution has key {
        id: UID,
        name: String,
        address: address,
        credentials: LinkedTable<String, Credential>,
        reputation_score: u64,
        verified: bool
    }

    public struct Credential has key, store {
        id: UID,
        title: String,
        description: String,
        issuer: address,
        issue_date: u64,
        expiry_date: Option<u64>,
        metadata: LinkedTable<String, String>,
        revoked: bool
    }

    public struct CredentialHolder has key {
        id: UID,
        holder: address,
        credentials: LinkedTable<String, Certificate>,
        verifications: LinkedTable<String, Verification>
    }

    public struct Certificate has key, store {
        id: UID,
        credential_id: ID,
        holder: address,
        issued_by: address,
        issue_date: u64,
        achievement_data: LinkedTable<String, String>
    }

    public struct Verification has store {
        verifier: address,
        verification_date: u64,
        valid_until: u64,
        verification_notes: String
    }

    // Gamification structs
    public struct SkillTree has key {
        id: UID,
        skills: LinkedTable<String, Skill>,
        prerequisites: LinkedTable<String, vector<String>>,
        owner: address
    }

    public struct Skill has store {
        name: String,
        level: u64,
        experience: u64,
        mastery_threshold: u64,
        endorsements: vector<Endorsement>
    }

    public struct Endorsement has store {
        endorser: address,
        weight: u64,
        timestamp: u64,
        notes: String
    }

    public struct Achievement has key, store {
        id: UID,
        name: String,
        description: String,
        points: u64,
        rarity: u8, // 1: Common, 2: Rare, 3: Epic, 4: Legendary
        requirements: vector<String>,
        holders: vector<address>
    }

    public struct Challenge has key {
        id: UID,
        name: String,
        description: String,
        start_time: u64,
        end_time: u64,
        required_credentials: vector<String>,
        reward_points: u64,
        participants: vector<address>,
        completed_by: vector<address>
    }

    public struct ReputationPoints has key {
        id: UID,
        holder: address,
        total_points: u64,
        point_history: LinkedTable<String, PointEntry>,
        level: u64,
        badges: vector<Badge>
    }

    public struct PointEntry has store {
        amount: u64,
        source: String,
        timestamp: u64,
        category: String
    }

    public struct Badge has store {
        name: String,
        category: String,
        level: u8,
        earned_date: u64,
        special_privileges: vector<String>
    }

    public struct LearningPath has key {
        id: UID,
        name: String,
        description: String,
        required_credentials: vector<String>,
        milestones: LinkedTable<u64, Milestone>,
        completion_reward: u64,
        participants: vector<address>
    }

    public struct Milestone has store {
        description: String,
        required_skills: vector<String>,
        reward_points: u64,
        completed_by: vector<address>
    }

    // Initialize platform
    fun init(ctx: &mut TxContext) {
        let platform = Platform {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            revenue: balance::zero(),
            verification_fee: 100 // Base fee in SUI
        };
        transfer::share_object(platform);
    }

    // Core certification functions
    public fun register_institution(
        platform: &Platform,
        name: String,
        ctx: &mut TxContext
    ) {
        let institution = Institution {
            id: object::new(ctx),
            name,
            address: tx_context::sender(ctx),
            credentials: linked_table::new(ctx),
            reputation_score: 0,
            verified: false
        };
        transfer::transfer(institution, tx_context::sender(ctx));
    }

    public fun create_credential(
        institution: &mut Institution,
        title: String,
        description: String,
        expiry_period: Option<u64>,
        ctx: &mut TxContext
    ) {
        assert!(institution.address == tx_context::sender(ctx), ENotAuthorized);
        
        let credential = Credential {
            id: object::new(ctx),
            title,
            description,
            issuer: institution.address,
            issue_date: tx_context::epoch(ctx),
            expiry_date: expiry_period,
            metadata: linked_table::new(ctx),
            revoked: false
        };

        linked_table::push_back(&mut institution.credentials, title, credential);
    }

    public fun issue_certificate(
        institution: &Institution,
        credential_title: String,
        holder_address: address,
        achievement_data: LinkedTable<String, String>,
        ctx: &mut TxContext
    ) {
        assert!(institution.address == tx_context::sender(ctx), ENotAuthorized);
        let credential = linked_table::borrow(&institution.credentials, credential_title);
        
        let certificate = Certificate {
            id: object::new(ctx),
            credential_id: object::id(credential),
            holder: holder_address,
            issued_by: institution.address,
            issue_date: tx_context::epoch(ctx),
            achievement_data
        };

        transfer::transfer(certificate, holder_address);
    }

    public fun verify_certificate(
        platform: &mut Platform,
        certificate: &Certificate,
        notes: String,
        valid_period: u64,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let payment_value = coin::value(&payment);
        assert!(payment_value >= platform.verification_fee, EInvalidCredential);
        
        let verification = Verification {
            verifier: tx_context::sender(ctx),
            verification_date: tx_context::epoch(ctx),
            valid_until: tx_context::epoch(ctx) + valid_period,
            verification_notes: notes
        };

        let payment_balance = coin::into_balance(payment);
        balance::join(&mut platform.revenue, payment_balance);
    }

    // Gamification functions
    public fun create_skill_tree(ctx: &mut TxContext) {
        let skill_tree = SkillTree {
            id: object::new(ctx),
            skills: linked_table::new(ctx),
            prerequisites: linked_table::new(ctx),
            owner: tx_context::sender(ctx)
        };
        transfer::transfer(skill_tree, tx_context::sender(ctx));
    }

    public fun add_skill(
        skill_tree: &mut SkillTree,
        name: String,
        mastery_threshold: u64,
        prerequisites: vector<String>,
        ctx: &mut TxContext
    ) {
        assert!(skill_tree.owner == tx_context::sender(ctx), ENotAuthorized);
        
        let skill = Skill {
            name: name,
            level: 0,
            experience: 0,
            mastery_threshold,
            endorsements: vector::empty()
        };

        linked_table::push_back(&mut skill_tree.skills, name, skill);
        linked_table::push_back(&mut skill_tree.prerequisites, name, prerequisites);
    }

    public fun endorse_skill(
        skill_tree: &mut SkillTree,
        skill_name: String,
        weight: u64,
        notes: String,
        ctx: &mut TxContext
    ) {
        let endorser = tx_context::sender(ctx);
        assert!(endorser != skill_tree.owner, EInvalidEndorsement);
        
        let skill = linked_table::borrow_mut(&mut skill_tree.skills, skill_name);
        let endorsement = Endorsement {
            endorser,
            weight,
            timestamp: tx_context::epoch(ctx),
            notes
        };
        vector::push_back(&mut skill.endorsements, endorsement);
    }

    public fun create_learning_path(
        name: String,
        description: String,
        required_credentials: vector<String>,
        completion_reward: u64,
        ctx: &mut TxContext
    ) {
        let learning_path = LearningPath {
            id: object::new(ctx),
            name,
            description,
            required_credentials,
            milestones: linked_table::new(ctx),
            completion_reward,
            participants: vector::empty()
        };
        transfer::share_object(learning_path);
    }

    public fun add_milestone(
        learning_path: &mut LearningPath,
        milestone_number: u64,
        description: String,
        required_skills: vector<String>,
        reward_points: u64,
        ctx: &mut TxContext
    ) {
        let milestone = Milestone {
            description,
            required_skills,
            reward_points,
            completed_by: vector::empty()
        };
        linked_table::push_back(&mut learning_path.milestones, milestone_number, milestone);
    }

    public fun create_challenge(
        name: String,
        description: String,
        start_time: u64,
        end_time: u64,
        required_credentials: vector<String>,
        reward_points: u64,
        ctx: &mut TxContext
    ) {
        let challenge = Challenge {
            id: object::new(ctx),
            name,
            description,
            start_time,
            end_time,
            required_credentials,
            reward_points,
            participants: vector::empty(),
            completed_by: vector::empty()
        };
        transfer::share_object(challenge);
    }

    public fun add_points(
        reputation: &mut ReputationPoints,
        amount: u64,
        source: vector<u8>,
        ctx: &mut TxContext
    ) {
        reputation.total_points = reputation.total_points + amount;
        reputation.level = calculate_level(reputation.total_points);
        
        let entry = PointEntry {
            amount,
            source: string::utf8(source),
            timestamp: tx_context::epoch(ctx),
            category: string::utf8(b"Achievement")
        };
        
        linked_table::push_back(
            &mut reputation.point_history,
            string::utf8(source),
            entry
        );
    }

    fun calculate_level(points: u64): u64 {
        points / 100 + 1
    }

    public fun award_badge(
        reputation: &mut ReputationPoints,
        name: String,
        category: String,
        level: u8,
        privileges: vector<String>,
        ctx: &mut TxContext
    ) {
        let badge = Badge {
            name,
            category,
            level,
            earned_date: tx_context::epoch(ctx),
            special_privileges: privileges
        };
        vector::push_back(&mut reputation.badges, badge);
    }

    public fun progress_learning_path(
        learning_path: &mut LearningPath,
        reputation: &mut ReputationPoints,
        milestone_number: u64,
        ctx: &mut TxContext
    ) {
        let participant = tx_context::sender(ctx);
        let milestone = linked_table::borrow_mut(&mut learning_path.milestones, milestone_number);
        
        vector::push_back(&mut milestone.completed_by, participant);
        add_points(reputation, milestone.reward_points, b"Learning Path Progress", ctx);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}