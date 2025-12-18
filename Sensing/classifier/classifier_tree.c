// Auto-generated decision tree classifier
// Accuracy: 0.4815

int classify_event(float* features) {
    if (features[25] <= 0.156149f) {
        if (features[30] <= 0.571526f) {
            if (features[38] <= 0.516850f) {
                if (features[6] <= 0.462831f) {
                    return 3; // normal
                } else {
                    if (features[57] <= 0.307517f) {
                        return 4; // turn
                    } else {
                        if (features[13] <= 0.887556f) {
                            return 0; // brake
                        } else {
                            if (features[39] <= 0.063562f) {
                                return 4; // turn
                            } else {
                                if (features[41] <= 0.811531f) {
                                    return 3; // normal
                                } else {
                                    return 1; // bump
                                }
                            }
                        }
                    }
                }
            } else {
                if (features[17] <= 0.145395f) {
                    if (features[11] <= 0.917256f) {
                        return 4; // turn
                    } else {
                        if (features[35] <= 0.956297f) {
                            if (features[43] <= 0.081519f) {
                                return 1; // bump
                            } else {
                                return 0; // brake
                            }
                        } else {
                            return 3; // normal
                        }
                    }
                } else {
                    if (features[34] <= 0.112578f) {
                        return 0; // brake
                    } else {
                        if (features[52] <= 0.356674f) {
                            if (features[13] <= 0.914238f) {
                                return 3; // normal
                            } else {
                                return 1; // bump
                            }
                        } else {
                            return 0; // brake
                        }
                    }
                }
            }
        } else {
            if (features[28] <= 0.092892f) {
                return 3; // normal
            } else {
                if (features[22] <= 0.622492f) {
                    return 0; // brake
                } else {
                    return 3; // normal
                }
            }
        }
    } else {
        if (features[19] <= 0.438382f) {
            return 2; // crash
        } else {
            if (features[16] <= 0.153465f) {
                if (features[14] <= 0.381496f) {
                    if (features[7] <= 0.062198f) {
                        return 3; // normal
                    } else {
                        if (features[25] <= 0.183816f) {
                            return 0; // brake
                        } else {
                            return 1; // bump
                        }
                    }
                } else {
                    return 1; // bump
                }
            } else {
                if (features[60] <= 0.340081f) {
                    return 1; // bump
                } else {
                    if (features[13] <= 0.927018f) {
                        return 3; // normal
                    } else {
                        return 1; // bump
                    }
                }
            }
        }
    }
}