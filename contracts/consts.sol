// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

library Consts {
    // basic game constants
    uint32 constant INITIAL_ARMY_SIZE = 500;
    uint32 constant INITIAL_POINTS = 0;
    uint32 constant INITIAL_TURNS = 10;
    uint32 constant MAX_ATTACK = 2000;
    uint32 constant MAX_DEFENSE = 2000;
    uint32 constant TURNS_NEEDED_FOR_MOBILIZE = 1;
    uint32 constant TURNS_NEEDED_FOR_ATTACK = 3;
    uint32 constant TURNS_NEEDED_FOR_CHANGE_DEFENSE = 3;
    uint256 constant TURN_INTERVAL = 1 hours;
    uint256 constant ATTACK_COOLDOWN = 1 hours;
    uint32 constant POINTS_FOR_ATTACK_WIN = 100;
    uint32 constant POINTS_PER_TURN_FOR_KING = 10;
    uint32 constant MAX_TURNS = 100;

    // Weather effect constants
    uint32 constant ADVANTAGE = 110;
    uint32 constant EXTREME_ADVANTAGE = 120;
    uint32 constant DISADVANTAGE = 90;
    uint32 constant EXTREME_DISADVANTAGE = 80;
    uint32 constant NO_EFFECT = 100;

}