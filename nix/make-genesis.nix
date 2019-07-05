{ block0_consensus
, consensus_leader_ids
, initial
, block0_date ? 1550822014
, isProduction ? false
, slots_per_epoch ? 60
, slot_duration
, epoch_stability_depth ? 10
, bft_slots_ratio ? 0
, consensus_genesis_praos_active_slot_coeff ? 0.1
, max_number_of_transactions_per_block ? 255
, linear_fees_constant
, linear_fees_coefficient
, linear_fees_certificate
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
    linear_fees = {
      constant = linear_fees_constant;
      coefficient = linear_fees_coefficient;
      certificate = linear_fees_certificate;
    };
    kes_update_speed = kes_update_speed;
  };
  initial = initial;
}
