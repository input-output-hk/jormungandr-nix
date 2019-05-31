{
  stdenv
, startDate ? 0
, slotsPerEpoch ? 5
, slotDuration ? 15
, epochStabilityDepth ? 10
, bftSlotsRatio ? 0.220
, consensusGenesisPraosActiveSlotCoeff ? 0.22
, maxTx ? 255
, allowAccountCreation ? true
, linearFeeConstant ? 2
, linearFeeCoefficient ? 1
, linearFeeCert ? 4
, kesUpdateSpeed ? 43200 # 12 hours
, jormungandr
, isProduction ? true
}:

let
  genesisAttrs = {
    blockchain_configuration = {
      block0_date = startDate;
      discrimination = if isProduction then "production" else "test";
      block0_genesis = "genesis";
      slots_per_epoch = slotsPerEpoch;
      slot_duration = slotDuration;
      epoch_stability_depth = epochStabilityDepth;
      consensus_leader_ids = [];
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
    initial_funds = [
    ];
    initial_certs = [
    ];

  };

in
builtins.toFile "genesis.yaml" (builtins.toJSON genesisAttrs)
