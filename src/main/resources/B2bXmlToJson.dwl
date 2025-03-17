%dw 2.0

// Helper Functions
fun asKey(val) = lower(removePrefix(removePrefix(val, "PIMB2B"), "AT_"))

fun removePrefix(val, xWord) = val replace xWord with ""

fun convertToContext(qualifierID, inputXML) = 
  (inputXML."STEP-ProductInformation".Qualifiers.*Qualifier[?(($.@ID == qualifierID))][0]).Context.@ID splitBy " " joinBy "_"

fun codeValueObject(obj) = {
  code: obj.@ID,
  value: obj
}

// Conversion Functions
fun convertValue(values, inputXML) = 
  (values.*Value map {
    (asKey($.@AttributeID)): 
      if ($.@ID?)
        if ($.@QualifierID? or $.@LOVQualifierID?)
          (convertToContext($.@QualifierID default $.@LOVQualifierID, inputXML)): codeValueObject($)
        else 
          codeValueObject($)
      else
        if ($.@QualifierID? or $.@LOVQualifierID?) 
          (convertToContext($.@QualifierID default $.@LOVQualifierID, inputXML)): $
        else 
          $
  } reduce ($$ ++ $))

fun convertValueGroups(values, inputXML) =
  (values.*ValueGroup map {
    (
      (asKey($.@AttributeID)): $.*Value map {
        (convertToContext($.@QualifierID, inputXML)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)
    )
  })

fun convertMultiValue(values, inputXML) = 
  (values.*MultiValue map (mulVal) -> (asKey(mulVal.@AttributeID)) : {
    (mulVal.*ValueGroup map ((valGroup) -> {
      (valGroup.*Value map 
        (convertToContext($.@QualifierID, inputXML)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      )
    })),
    ((mulVal.*Value groupBy (convertToContext($.@QualifierID, inputXML))) mapObject ((value, key, index) -> (key): value map if($.@ID?) codeValueObject($) else $))
  })

fun convertEntity(entityObject, inputXML) =
  {
    (if(entityObject.MetaData?) {
      (entityObject.MetaData.*Value default [] map {
        (asKey($.@AttributeID)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)),
      (entityObject.MetaData.*ValueGroup default [] map {
        (asKey($.@AttributeID)): $.*Value map {
          (convertToContext($.@QualifierID, inputXML)): 
            if ($.@ID?)
              codeValueObject($)
            else
              $
        } reduce ($$ ++ $)
      })
    } else {}),
    (if (entityObject.Values.*Value?)
      (entityObject.Values.*Value default [] map {
        (asKey($.@AttributeID)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $))
    else
      {})
  }

fun convertAssets(assetsArray, inputXML) =
  (assetsArray map (asset) -> {
    ((asset.@) mapObject {
      (asKey($$)): 
        if (($$ as String) == "Type")
          asKey($)
        else
          $
    }),
    (asset.MetaData.*Value map {
      (asKey($.@AttributeID)): 
        ($.@QualifierID): $

    }),
    (asset.MetaData.*ValueGroup map {
      (asKey($.@AttributeID)): $.*Value map {
        (convertToContext($.@QualifierID, inputXML)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)
    })
  }) groupBy ($."type")

fun b2bGTINS(entity, inputXML) = {
  (if(entity.@UserTypeID == "B2B_GTIN") (entity.@ID):{
    (entity.Values.*Value map {
      (asKey($.@AttributeID)): 
        if ($.@ID?)
          codeValueObject($)
        else
          $
    } reduce ($$ ++ $)),
    (entity.Values.*ValueGroup map {
      (asKey($.@AttributeID)): $.*Value map {
        (convertToContext($.@QualifierID, inputXML)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)
    })
  } else if (entity.*Entity?) (entity.*Entity map (b2bGTINS($, inputXML))) else {})
}

// Main Function
fun main(payload) = do {
  var inputXML = payload
  var styles = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Style"))]
  var colors = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Color"))]
  var size_variants = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Size_Variant"))]
  var entities = inputXML."STEP-ProductInformation".Entities.*Entity
  var GTINS = entities map (entity) -> b2bGTINS(entity, inputXML)
---
  {
    "styles": styles as Array map {
      (($.@) mapObject { (asKey($$)): $ }),
      (asset_references: convertAssets($.*AssetCrossReference, inputXML)) if (styles.AssetCrossReference?),
      (convertValue($.Values, inputXML)),
      (convertValueGroups($.Values, inputXML)),
      (convertMultiValue($.Values, inputXML))
    },
    "colors": colors as Array map (color) -> { 
      ((color.@) mapObject { (asKey($$)):$}), 
      (asset_references: convertAssets(color.*AssetCrossReference, inputXML)) if (color.AssetCrossReference?), 
      (convertValue(color.Values, inputXML)),
      (convertValueGroups(color.Values, inputXML)), 
      (convertMultiValue(color.Values, inputXML)), 
    }, 
    "size_variants": size_variants as Array map (size) -> ({ 
      ((size.@) mapObject { (asKey($$)):$}), 
      (convertValue(size.Values, inputXML)),
      (if(size.Values.*ValueGroup?) convertValueGroups(size.Values, inputXML) else {}) , 
      (if (size.Values.*MultiValue?) convertMultiValue(size.Values, inputXML) else {}), 
      ( GTINS[(size.*EntityCrossReference[?($.@Type == "REFERENCEB2BSIZETOGTIN")].@EntityID)[0]][0]),
      (size.*EntityCrossReference map (entityRef) -> if(entityRef.MetaData?) convertEntity(entityRef, inputXML) else {} ) 
    }) distinctBy ($$),
  }
}
---
main(payload)