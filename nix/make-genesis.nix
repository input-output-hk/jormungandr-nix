{ consensusMode
, consensusLeaderIds
, initialCerts
, faucets
, startDate ? 1550822014
, isProduction ? false
, slotsPerEpoch ? 60
, slotDuration ? 10
, epochStabilityDepth ? 10
, bftSlotsRatio ? if (consensusMode == "bft") then 0 else 0.1
, consensusGenesisPraosActiveSlotCoeff ? 0.1
, maxTx ? 255
, allowAccountCreation ? true
, linearFeeConstant ? 10
, linearFeeCoefficient ? 0
, linearFeeCert ? 0
, kesUpdateSpeed ? 43200 # 12 hours
, ...
}:
builtins.toJSON {
  blockchain_configuration = {
    block0_date = startDate;
    discrimination = if isProduction then "production" else "test";
    block0_consensus = consensusMode;
    slots_per_epoch = slotsPerEpoch;
    slot_duration = slotDuration;
    epoch_stability_depth = epochStabilityDepth;
    consensus_leader_ids = consensusLeaderIds;
    bft_slots_ratio = bftSlotsRatio;
    consensus_genesis_praos_active_slot_coeff = consensusGenesisPraosActiveSlotCoeff;
    max_number_of_transactions_per_block = maxTx;
    allow_account_creation = allowAccountCreation;
    linear_fee = {
      constant = linearFeeConstant;
      coefficient = linearFeeCoefficient;
      certificate = linearFeeCert;
    };
    kes_update_speed = kesUpdateSpeed;
  };
  initial_funds = faucets;
  initial_certs = initialCerts;
}
