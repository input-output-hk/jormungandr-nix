{ block0_consensus
, consensus_leader_ids
, initial_certs
, initial_funds
, block0_date ? 1550822014
, isProduction ? false
, slots_per_epoch ? 60
, slot_duration ? 10
, epoch_stability_depth ? 10
, bft_slots_ratio ? if (block0_consensus == "bft") then 0 else 0.1
, consensus_genesis_praos_active_slot_coeff ? 0.1
, max_number_of_transactions_per_block ? 255
, allow_account_creation ? true
, linear_fee_constant ? 10
, linear_fee_coefficient ? 0
, linear_fee_certificate ? 0
, kes_update_speed ? 43200 # 12 hours
, ...
}:
builtins.toJSON {
  blockchain_configuration = {
    block0_date = block0_date;
    discrimination = if isProduction then "production" else "test";
    block0_consensus = block0_consensus;
    slots_per_epoch = slots_per_epoch;
    slot_duration = slot_duration;
    epoch_stability_depth = epoch_stability_depth;
    consensus_leader_ids = consensus_leader_ids;
    bft_slots_ratio = bft_slots_ratio;
    consensus_genesis_praos_active_slot_coeff = consensus_genesis_praos_active_slot_coeff;
    max_number_of_transactions_per_block = max_number_of_transactions_per_block;
    allow_account_creation = allow_account_creation;
    linear_fee = {
      constant = linear_fee_constant;
      coefficient = linear_fee_coefficient;
      certificate = linear_fee_certificate;
    };
    kes_update_speed = kes_update_speed;
  };
  initial_funds = initial_funds;
  initial_certs = initial_certs;
}
