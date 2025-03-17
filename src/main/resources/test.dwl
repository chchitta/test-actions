%dw 2.0
var inputXML = readUrl("classpath://B2B_OutBound_2025-02-13_06.28.58.xml", "application/xml")
var styles = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Style"))]
var colors = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Color"))]
var size_variants = inputXML."STEP-ProductInformation".Products.*Product[?(($.@UserTypeID == "GB2B_Size_Variant"))]
var entities = inputXML."STEP-ProductInformation".Entities.*Entity

fun asKey(val) =
  lower(removePrefix(removePrefix(val, "PIMB2B"), "AT_"))

fun codeValueObject(obj) = {
  code: obj.@ID,
  value: obj
}

fun removePrefix(val, xWord) =
  val replace xWord with ""



fun convertValueGroups(values) =
  (values.*ValueGroup map {
    (
      (asKey($.@AttributeID)): $.*Value map {
        (convertToContext($.@QualifierID)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)
    )
  })


fun convertMultiValue(values) = 
  (values.*MultiValue map (mulVal) -> (asKey(mulVal.@AttributeID)) : {
    (mulVal.*ValueGroup map ((valGroup) -> {
      (valGroup.*Value map 
        (convertToContext($.@QualifierID)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      )
    })),
    ((mulVal.*Value groupBy (convertToContext($.@QualifierID))) mapObject ((value, key, index) -> (key): value map if($.@ID?) codeValueObject($) else $))
  })


fun convertToContext(qualifierID) =
  (inputXML."STEP-ProductInformation".Qualifiers.*Qualifier[?(($.@ID == qualifierID))][0]).Context.@ID splitBy " " joinBy "_"



fun convertObjects(arrayOfObjects: Array) =
  arrayOfObjects map {
    (($.@) mapObject {
      (asKey($$)): $
    }),
    (convertValueGroups($.Values)),
    (convertMultiValue($.Values))
  }

fun convertEntity(entityObject) =
  {
    // ((entityObject.@) mapObject {
    //   (asKey($$)): $
    // }),
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
          (convertToContext($.@QualifierID)): 
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

fun convertAssets(assetsArray) =
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
        (convertToContext($.@QualifierID)): 
          if ($.@ID?)
            codeValueObject($)
          else
            $
      } reduce ($$ ++ $)
    })
  }) groupBy ($."type")


fun convertValue(values) = 
  (values.*Value map {
	(asKey($.@AttributeID)): 
	  if ($.@ID?)
		if ($.@QualifierID? or $.@LOVQualifierID?)
		  (convertToContext($.@QualifierID  default $.@LOVQualifierID)): codeValueObject($)
		else 
		  codeValueObject($)
	  else
		if ($.@QualifierID? or $.@LOVQualifierID?) 
			(convertToContext($.@QualifierID  default $.@LOVQualifierID)): $
		else 
			$
  } reduce ($$ ++ $))

fun b2bGTINS(entity) = {
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
                (convertToContext($.@QualifierID)): 
                    if ($.@ID?)
                        codeValueObject($)
                    else
                        $
            } reduce ($$ ++ $)
        })
    } else if (entity.*Entity?) (entity.*Entity map (b2bGTINS($))) else {

    })
}

var GTINS = entities map (entity) -> b2bGTINS(entity)

---
{ 
  "styles": styles as Array map {
    (($.@) mapObject { (asKey($$)): $ }),
    (asset_references: convertAssets($.*AssetCrossReference)) if (styles.AssetCrossReference?),
    (convertValue($.Values)),
    (convertValueGroups($.Values)),
    (convertMultiValue($.Values))
  },
  "colors": colors as Array map (color) -> { 
    ((color.@) mapObject { (asKey($$)):$}), 
    (asset_references: convertAssets(color.*AssetCrossReference)) if (color.AssetCrossReference?), 
    (convertValue(color.Values)),
    (convertValueGroups(color.Values)), 
    (convertMultiValue(color.Values)), 
  }, 
  "size_variants": size_variants as Array map (size) -> ({ 
    ((size.@) mapObject { (asKey($$)):$}), 
    (convertValue(size.Values)),
    (if(size.Values.*ValueGroup?) convertValueGroups(size.Values) else {}) , 
    (if (size.Values.*MultiValue?) convertMultiValue(size.Values) else {}), 
    ( GTINS[(size.*EntityCrossReference[?($.@Type == "REFERENCEB2BSIZETOGTIN")].@EntityID)[0]][0]),
    (size.*EntityCrossReference map (entityRef) -> if(entityRef.MetaData?) convertEntity(entityRef) else {} ) 
  }) distinctBy ($$),
}