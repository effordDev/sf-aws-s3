global class AWSS3BucketVisibilityPicklist extends VisualEditor.DynamicPickList {
    
    global override VisualEditor.DataRow getDefaultValue(){
        return new VisualEditor.DataRow('external', 'external');
    }

    global override VisualEditor.DynamicPickListRows getValues() {

        VisualEditor.DynamicPickListRows  values = new VisualEditor.DynamicPickListRows();
            values.addRow(new VisualEditor.DataRow('external', 'external'));
            values.addRow(new VisualEditor.DataRow('internal', 'internal'));
        return values;
    }
}