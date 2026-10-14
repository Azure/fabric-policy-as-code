function ConvertFrom-FpacJsonElement {
    param (
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement] $Element
    )

    switch ($Element.ValueKind) {
        Object {
            $value = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                $value[$property.Name] = ConvertFrom-FpacJsonElement -Element $property.Value
            }
            return [pscustomobject] $value
        }
        Array {
            $values = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $Element.EnumerateArray()) {
                $values.Add((ConvertFrom-FpacJsonElement -Element $entry))
            }
            return ,$values.ToArray()
        }
        String { return $Element.GetString() }
        Number { return $Element.GetDecimal() }
        True { return $true }
        False { return $false }
        Null { return $null }
        default { throw "Unsupported JSON value kind '$($Element.ValueKind)' in FPAC settings." }
    }
}
