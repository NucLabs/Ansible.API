function ConvertTo-AAPDynamicParam {
    <#
    .SYNOPSIS
        Converts an AWX/AAP survey_spec into a RuntimeDefinedParameterDictionary.
    .DESCRIPTION
        Takes the spec array from GET /api/v2/job_templates/{id}/survey_spec/
        and generates typed PowerShell dynamic parameters. Stores the list of
        survey variable names in $Script:AAPSurveyParamNames.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [Parameter(Mandatory)]
        [object[]]$SurveySpec
    )

    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $Script:AAPSurveyParamNames = [System.Collections.Generic.List[string]]::new()

    foreach ($field in $SurveySpec) {
        $paramName = $field.variable
        $Script:AAPSurveyParamNames.Add($paramName)

        # Determine .NET type
        $paramType = switch ($field.type) {
            'integer'        { [int] }
            'float'          { [double] }
            'multiselect'    { [string[]] }
            default          { [string] }  # text, textarea, password, multiplechoice
        }

        # Build attributes
        $attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        $paramAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $paramAttribute.Mandatory = [bool]$field.required
        if ($field.question_name) {
            $paramAttribute.HelpMessage = $field.question_name
        }
        $attributes.Add($paramAttribute)

        # ValidateSet for choice fields
        if ($field.type -in 'multiplechoice', 'multiselect' -and $field.choices) {
            $choiceList = if ($field.choices -is [array]) {
                $field.choices
            } else {
                ($field.choices -split "`n") | Where-Object { $_.Trim() -ne '' }
            }
            if ($choiceList.Count -gt 0) {
                $validateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$choiceList)
                $attributes.Add($validateSet)
            }
        }

        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
            $paramName,
            $paramType,
            $attributes
        )

        # Set default value if provided and not empty
        if ($null -ne $field.default -and "$($field.default)" -ne '') {
            $dynParam.Value = $field.default
        }

        $paramDictionary.Add($paramName, $dynParam)
    }

    return $paramDictionary
}
