function New-FpacPlanBucket {
    return [ordered]@{
        new             = [ordered]@{}
        update          = [ordered]@{}
        replace         = [ordered]@{}
        adopt           = [ordered]@{}
        delete          = [ordered]@{}
        numberOfChanges = 0
        numberUnchanged = 0
    }
}
